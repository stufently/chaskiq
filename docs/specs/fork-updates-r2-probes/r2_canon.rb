# frozen_string_literal: true

# Per-cop semantic-equivalence checker for fork-updates-r2 (run by r2_equiv_probe.py in the CI image).
#
# Usage: ruby r2_canon.rb <base_dir> <tree_dir> <list_file>
#   <list_file>: one line per changed file: "<relative path>\t<Cop1>,<Cop2>,..." — the R2 cops
#   whose rewrite may explain differences in that file (the cops whose BASE .rubocop_todo.yml
#   section lists the file, plus declared cascades).
# Output, one line per file:
#   SAME <path>                       the syntax trees are identical (only layout/comments differ)
#   EXPLAINED <path> <Cop>,<Cop>      identical after the rewrites of exactly these cops (each one
#                                     is needed: without it the trees differ)
#   DIFF <path> <where>               not explained by the allowed cops (first differing node)
#   ERROR <path> <message>            parse error or internal error
#   NEWWARN <path> <message>          `ruby -wc` warns about the tree file where BASE did not
#   LINES <path>                      a line-sensitive file (__LINE__, caller, caller_locations,
#                                     source_location, eval, *_eval/*_exec with a string) that is
#                                     not SAME with every node on its old line: R2 must not move it
#
# Method. Both versions are parsed with Prism into plain trees without locations (line, column,
# keyword/operator positions) and without the NEWLINE flag; everything else is kept: node types,
# names, flags, literal values (strings as encoding + bytes, floats as IEEE bytes), magic comments
# and the __END__ data. Two renamings are always applied because they are exact identities:
# `unless C then A else B end` == `if C then B else A end` (both become :Cond, ternary and
# modifier forms included; an empty branch is nil), StatementsNode becomes a plain list, and
# HashNode becomes :HashLit.
# EmptyStringInsideInterpolation relies on nil.to_s == "": the probe refuses the tree if app/,
# lib/ or config/ reopen NilClass (gems are out of reach of the check). Then, per allowed cop, a rewrite that maps both the old and the new
# form of that cop's transformation to one canonical form. Every rewrite is an equivalence in Ruby
# semantics under the stated conditions (see RULES below); when a condition does not hold the
# rewrite is not applied and the difference stays visible.
require "open3"
require "prism"
require "ripper"

module R2Canon
  NEWLINE = Prism::NodeFlags::NEWLINE
  SKIP_FIELDS = [Prism::Reflection::LocationField, Prism::Reflection::OptionalLocationField].freeze
  FORWARD_UNSAFE_CALLS = %i[binding local_variables eval instance_eval class_eval module_eval].freeze

  # Cop => rewrites it may use.
  RULES = {
    "Style/RedundantParentheses" => %i[parens],          # (x) == x for one expression (not under defined?);
                                                         # a && (b && c) == (a && b) && c (same for ||)
    "Style/HashAsLastArrayItem" => %i[array_kwhash],     # [a, k: v] == [a, { k: v }] (no **splat)
    "Style/RedundantReturn" => %i[tail_return],          # `return x` as the last expression of a method == x
    "Style/GuardClause" => %i[guard],                    # at the tail of a method: `return if C; R` == `unless C; R; end`
    "Style/ArgumentsForwarding" => %i[anon_rest anon_kwrest anon_block],
    "Naming/BlockForwarding" => %i[anon_block],          # def f(&b) g(&b) == def f(&) g(&) when b is only forwarded
    "Style/SuperArguments" => %i[zsuper],                # super(a, b) == super when def f(a, b) and a, b never reassigned
    "Style/EmptyStringInsideInterpolation" => %i[interp_empty], # "#{c ? x : ''}" == "#{x if c}"
    "Style/IfUnlessModifier" => [],                      # no rewrite: modifier and block if/unless parse the same
    "Style/DirectiveScope" => []                         # comments only
  }.freeze

  module_function

  # ---- plain tree ------------------------------------------------------------------------------
  def plain(node)
    return nil if node.nil?

    h = { t: node.class.name.split("::").last.to_sym }
    Prism::Reflection.fields_for(node.class).each do |f|
      next if SKIP_FIELDS.any? { |k| f.is_a?(k) }

      h[f.name] = plain_field(f, node.public_send(f.name)) unless f.is_a?(Prism::Reflection::FlagsField)
    end
    h[:flags] = node.send(:flags) & ~NEWLINE
    h
  end

  def plain_field(field, value)
    case field
    when Prism::Reflection::NodeField, Prism::Reflection::OptionalNodeField then plain(value)
    when Prism::Reflection::NodeListField then value.map { |v| plain(v) }
    when Prism::Reflection::StringField then [value.encoding.name, value.bytes]
    when Prism::Reflection::FloatField then [value].pack("G").bytes
    else value
    end
  end

  def parse(src)
    r = Prism.parse(src)
    raise "parse error: #{r.errors.first.message} (line #{r.errors.first.location.start_line})" if r.errors.any?

    magic = r.magic_comments.map { |m| [m.key, m.value] }
    data = r.data_loc&.slice
    [plain(r.value), magic, data]
  end

  # ---- rewrites --------------------------------------------------------------------------------
  def canon(tree, rules)
    @rules = rules
    walk(tree, nil)
  end

  def on?(rule) = @rules.include?(rule)

  def walk(obj, parent_t)
    case obj
    when Array then obj.map { |x| walk(x, parent_t) }
    when Hash then walk_node(obj, parent_t)
    else obj
    end
  end

  def walk_node(node, parent_t)
    kids = node.to_h { |k, v| [k, k == :t ? v : walk(v, node[:t])] }
    rewrite(kids, parent_t)
  end

  def rewrite(n, parent_t)
    case n[:t]
    when :StatementsNode then on?(:guard) ? return_pairs(n[:body]) : n[:body]
    when :IfNode then cond(n[:predicate], n[:statements], else_body(n[:subsequent]))
    when :UnlessNode then cond(n[:predicate], else_body(n[:else_clause]), n[:statements])
    when :ElseNode then n
    when :HashNode then { t: :HashLit, elements: n[:elements] }
    when :ArrayNode then array_kwhash(n)
    when :ParenthesesNode then parens(n, parent_t)
    when :AndNode, :OrNode then flatten_logic(n)
    when :EmbeddedStatementsNode then interp_empty(n)
    when :ForwardingSuperNode then { t: :ZSuper, block: n[:block] }
    when :DefNode then def_node(n)
    else n
    end
  end

  # Anywhere: `return a if c; return b` == `if c then return a else return b end` (both exit).
  def return_pairs(list)
    out = []
    list.each do |stmt|
      prev = out[-1]
      if return_stmt?(stmt) && prev.is_a?(Hash) && prev[:t] == :Cond && prev[:else].nil? &&
         prev[:then].is_a?(Array) && prev[:then].size == 1 && return_stmt?(prev[:then][0])
        out[-1] = prev.merge(else: [stmt])
      elsif return_stmt?(stmt) && prev.is_a?(Hash) && prev[:t] == :Cond && prev[:then].nil? &&
            prev[:else].is_a?(Array) && prev[:else].size == 1 && return_stmt?(prev[:else][0])
        out[-1] = prev.merge(then: [stmt])
      else
        out << stmt
      end
    end
    out
  end

  def return_stmt?(node) = node.is_a?(Hash) && node[:t] == :ReturnNode

  def else_body(sub)
    return nil if sub.nil?
    return [sub] if sub[:t] == :Cond # elsif chain

    sub[:statements]
  end

  def cond(pred, then_b, else_b)
    { t: :Cond, pred: pred, then: blank(then_b), else: blank(else_b) }
  end

  def blank(list) = list.nil? || list.empty? ? nil : list

  def array_kwhash(n)
    return n unless on?(:array_kwhash)

    els = n[:elements].map do |e|
      if e[:t] == :KeywordHashNode && e[:elements].none? { |a| a[:t] == :AssocSplatNode }
        { t: :HashLit, elements: e[:elements] }
      else
        e
      end
    end
    n.merge(elements: els)
  end

  def parens(n, parent_t)
    return n unless on?(:parens) && parent_t != :DefinedNode

    body = n[:body]
    body.is_a?(Array) && body.size == 1 ? body[0] : n
  end

  def flatten_logic(n)
    return n unless on?(:parens)

    kind = n[:t]
    items = [n[:left], n[:right]].flat_map { |x| x.is_a?(Hash) && x[:t] == :"#{kind}Chain" ? x[:items] : [x] }
    { t: :"#{kind}Chain", items: items }
  end

  def empty_string?(list)
    list.is_a?(Array) && list.size == 1 && list[0][:t] == :StringNode && list[0][:unescaped][1].empty?
  end

  def interp_empty(n)
    st = n[:statements]
    return n unless on?(:interp_empty) && st.is_a?(Array) && st.size == 1 && st[0][:t] == :Cond

    c = st[0]
    c = c.merge(then: nil) if empty_string?(c[:then])
    c = c.merge(else: nil) if empty_string?(c[:else])
    n.merge(statements: [c])
  end

  # ---- method-level rewrites -------------------------------------------------------------------
  def def_node(n)
    @params_out = nil
    @locals_drop = []
    params = n[:parameters]
    body = n[:body]
    body = forward_rest(params, body) if on?(:anon_rest)
    body = forward_kwrest(params, body) if on?(:anon_kwrest)
    body = forward_block(params, body) if on?(:anon_block)
    params = @params_out || params
    @params_out = nil
    body = zsuper(params, body) if on?(:zsuper)
    # an anonymous parameter is not a local: Prism lists only named ones
    n.merge(parameters: params, body: tail(body), locals: n[:locals] - @locals_drop)
  end

  # The value of a method is its last expression; `return` there is the same value.
  def tail(body)
    case body
    when Array then tail_list(body)
    when Hash then body[:t] == :BeginNode && body[:else_clause].nil? ? body.merge(statements: tail(body[:statements])) : body
    else body
    end
  end

  def tail_list(list)
    return list if list.empty?

    i = nil
    i = list.each_index.find { |k| k < list.size - 1 && guard?(list[k]) } if on?(:guard)
    return list[0...i] + [guard_cond(list[i], tail_list(list[(i + 1)..]))] if i

    last = tail_node(list[-1])
    list[0...-1] + [last]
  end

  def tail_node(node)
    return node unless node.is_a?(Hash)

    case node[:t]
    when :ReturnNode then on?(:tail_return) ? return_value(node) : node
    when :Cond then node.merge(then: node[:then] && tail_list(node[:then]), else: node[:else] && tail_list(node[:else]))
    else node
    end
  end

  def return_value(node)
    args = node.dig(:arguments, :arguments)
    return { t: :NilNode, flags: Prism::NodeFlags::STATIC_LITERAL } if args.nil? || args.empty?
    return node if args.size > 1 || args[0][:t] == :SplatNode

    args[0]
  end

  def bare_return?(list)
    list.is_a?(Array) && list.size == 1 && list[0][:t] == :ReturnNode && list[0][:arguments].nil?
  end

  def guard?(node)
    node.is_a?(Hash) && node[:t] == :Cond &&
      ((bare_return?(node[:then]) && node[:else].nil?) || (bare_return?(node[:else]) && node[:then].nil?))
  end

  # `return if C; R` -> unless C; R; end   and   `return unless C; R` -> if C; R; end (at the tail)
  def guard_cond(guard, rest)
    if guard[:then]
      cond(guard[:pred], nil, rest)
    else
      cond(guard[:pred], rest, nil)
    end
  end

  # ---- anonymous forwarding (*, **, &) ---------------------------------------------------------
  def forward_rest(params, body)
    forward(params, body, :rest, :SplatNode, :expression)
  end

  def forward_kwrest(params, body)
    forward(params, body, :keyword_rest, :AssocSplatNode, :value)
  end

  def forward_block(params, body)
    forward(params, body, :block, :BlockArgumentNode, :expression)
  end

  def forward(params, body, slot, use_t, use_field)
    params = @params_out || params
    param = params && params[slot]
    name = param && param[:name]
    # The whole method is scanned: parameter defaults (`x = local_variables`, `y = block`) as well
    # as the body; only the forwarded parameter itself is left out.
    return body unless name && forwardable?([params.merge(slot => nil), body], name, use_t, use_field)

    @params_out = params.merge(slot => param.merge(name: nil))
    @locals_drop << name
    strip_uses(body, name, use_t, use_field)
  end

  def forwardable?(body, name, use_t, use_field)
    ok = true
    visit(body, nil) do |node, parent|
      ok = false if lvar_read?(node, name) && !(parent && parent[:t] == use_t && parent[use_field].equal?(node))
      ok = false if node.key?(:name) && node[:name] == name && !lvar_read?(node, name) && node[:t] != :CallNode
      ok = false if node[:t] == :CallNode && FORWARD_UNSAFE_CALLS.include?(node[:name])
    end
    ok
  end

  def lvar_read?(node, name) = node[:t] == :LocalVariableReadNode && node[:name] == name

  def strip_uses(obj, name, use_t, use_field)
    case obj
    when Array then obj.map { |x| strip_uses(x, name, use_t, use_field) }
    when Hash
      kids = obj.to_h { |k, v| [k, k == :t ? v : strip_uses(v, name, use_t, use_field)] }
      kids[:t] == use_t && kids[use_field].is_a?(Hash) && lvar_read?(kids[use_field], name) ? kids.merge(use_field => nil) : kids
    else obj
    end
  end

  def visit(obj, parent, &blk)
    case obj
    when Array then obj.each { |x| visit(x, parent, &blk) }
    when Hash
      yield obj, parent
      obj.each { |k, v| visit(v, obj, &blk) unless k == :t || (v.is_a?(Hash) && v[:t] == :DefNode) }
    end
  end

  # ---- super(a, b) == super --------------------------------------------------------------------
  def zsuper(params, body)
    names = simple_params(params)
    return body if names.nil? || names.empty? || written?(body, names)

    swap_super(body, names)
  end

  def simple_params(params)
    return [] if params.nil?
    return nil unless %i[optionals posts keywords].all? { |k| params[k].empty? } && params[:rest].nil? && params[:keyword_rest].nil?
    return nil unless params[:requireds].all? { |r| r[:t] == :RequiredParameterNode }

    params[:requireds].map { |r| r[:name] }
  end

  def written?(body, names)
    hit = false
    visit(body, nil) do |node, _|
      hit = true if node[:t] != :LocalVariableReadNode && node[:t] != :CallNode && node.key?(:name) && names.include?(node[:name])
    end
    hit
  end

  def swap_super(obj, names)
    case obj
    when Array then obj.map { |x| swap_super(x, names) }
    when Hash
      return obj if obj[:t] == :BlockNode || obj[:t] == :LambdaNode || obj[:t] == :DefNode

      kids = obj.to_h { |k, v| [k, k == :t ? v : swap_super(v, names)] }
      explicit_super?(kids, names) ? { t: :ZSuper, block: kids[:block] } : kids
    else obj
    end
  end

  def explicit_super?(node, names)
    return false unless node[:t] == :SuperNode && (node[:block].nil? || node[:block][:t] == :BlockNode)

    args = node.dig(:arguments, :arguments) || []
    args.map { |a| a[:t] == :LocalVariableReadNode && a[:depth].zero? ? a[:name] : nil } == names
  end

  # ---- comparison ------------------------------------------------------------------------------
  def first_diff(left, right, where = "")
    if left.is_a?(Hash) && right.is_a?(Hash)
      (left.keys | right.keys).each do |k|
        d = first_diff(left[k], right[k], "#{where}/#{left[:t] || '?'}.#{k}")
        return d if d
      end
      nil
    elsif left.is_a?(Array) && right.is_a?(Array)
      [left.size, right.size].min.times do |i|
        d = first_diff(left[i], right[i], "#{where}[#{i}]")
        return d if d
      end
      left.size == right.size ? nil : "#{where}: length #{left.size} <> #{right.size}"
    elsif left != right
      "#{where}: #{short(left)} <> #{short(right)}"
    end
  end

  def short(x) = x.is_a?(Hash) ? x[:t].inspect : x.inspect[0, 80]

  def rules_for(cops) = cops.flat_map { |c| RULES.fetch(c) }.uniq

  def check(base_path, tree_path, rel, cops)
    bsrc = File.read(base_path)
    tsrc = File.read(tree_path)
    puts verdict(bsrc, tsrc, rel, cops)
    puts "LINES #{rel}" if (line_sensitive?(bsrc) || line_sensitive?(tsrc)) && line_sig(bsrc) != line_sig(tsrc)
    (warnings(tree_path) - warnings(base_path)).each { |w| puts "NEWWARN #{rel} #{w}" }
  rescue StandardError, SyntaxError => e
    puts "ERROR #{rel} #{e.class}: #{e.message.lines.first&.strip}"
  end

  def verdict(bsrc, tsrc, rel, cops)
    b = parse(bsrc)
    t = parse(tsrc)
    return "SAME #{rel}" if canon(b, []) == canon(t, [])

    d = first_diff(canon(b, rules_for(cops)), canon(t, rules_for(cops)))
    return "DIFF #{rel} #{d}" if d

    needed = cops.select do |c|
      rest = rules_for(cops - [c])
      canon(b, rest) != canon(t, rest)
    end
    # Two allowed cops with the same rewrite (ArgumentsForwarding and BlockForwarding for `&`):
    # neither is needed alone; name the ones that suffice alone, joined by "|".
    needed = cops.select { |c| canon(b, rules_for([c])) == canon(t, rules_for([c])) }.map { |c| c } if needed.empty?
    "EXPLAINED #{rel} #{needed.join(needed.size > 1 && cops.size == needed.size ? '|' : ',')}"
  end

  # Node types with their start lines, in order: equal only for the same tree on the same lines.
  def line_sig(src)
    out = []
    stack = [Prism.parse(src).value]
    until stack.empty?
      n = stack.pop
      out << [n.class.name, n.location.start_line]
      stack.concat(n.compact_child_nodes.reverse)
    end
    out
  end

  LINE_IDENTS = %w[caller caller_locations source_location eval].freeze
  STRING_EVALS = %w[class_eval module_eval instance_eval class_exec module_exec instance_exec].freeze

  # `x.eval(...)` on another receiver (Redis#eval with a Lua script) is not Ruby eval; only bare
  # eval and binding/Kernel/TOPLEVEL_BINDING.eval are.
  EVAL_RECEIVERS = %w[binding Kernel TOPLEVEL_BINDING].freeze

  def line_sensitive?(src)
    toks = Ripper.lex(src).map { |(_, type, text, _)| [type, text] }.reject { |(type, _)| type == :on_sp }
    toks.each_with_index.any? do |(type, text), i|
      (type == :on_kw && text == "__LINE__") ||
        (type == :on_ident && LINE_IDENTS.include?(text) && !(text == "eval" && foreign_receiver?(toks, i))) ||
        (type == :on_ident && STRING_EVALS.include?(text) && string_next?(toks, i))
    end
  end

  def foreign_receiver?(toks, idx)
    return false unless idx >= 2 && %i[on_period on_op].include?(toks[idx - 1][0]) && %w[. &.].include?(toks[idx - 1][1])

    !EVAL_RECEIVERS.include?(toks[idx - 2][1])
  end

  def string_next?(toks, idx)
    nxt = toks[(idx + 1)..].find { |(type, _)| !%i[on_sp on_lparen].include?(type) }
    nxt && %i[on_tstring_beg on_heredoc_beg].include?(nxt[0])
  end

  def warnings(path)
    _out, err, _st = Open3.capture3("ruby", "-wc", path)
    err.lines.filter_map { |l| l[/warning: .*/]&.strip }.uniq
  end
end

if $PROGRAM_NAME == __FILE__
  base_dir, tree_dir, list = ARGV
  File.readlines(list, chomp: true).each do |line|
    rel, cops = line.split("\t")
    R2Canon.check(File.join(base_dir, rel), File.join(tree_dir, rel), rel, cops.to_s.split(","))
  end
end
