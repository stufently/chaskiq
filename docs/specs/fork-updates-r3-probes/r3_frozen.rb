# frozen_string_literal: true

# Static checker for fork-updates-r3 (`# frozen_string_literal: true` in the files of the old todo).
#
#   ruby r3_frozen.rb shape   <base_dir> <tree_dir> <list>   per-file: the change is exactly the magic
#                                                           comment (+ blank line), AST unchanged
#   ruby r3_frozen.rb freeze  <base_dir> <tree_dir> <list>   per-file: only `<frozen literal>.freeze`
#                                                           -> `<frozen literal>` (Style/RedundantFreeze)
#   ruby r3_frozen.rb mutate  <tree_dir> <list> <all_list>   literals of the listed files that can reach
#                                                           a mutation (see below)
#
# <list> / <all_list>: one repo-relative path per line. <all_list> = every Ruby file of app/, lib/,
# config/, spec/ (the places a literal of a listed file can travel to by a method call).
#
# shape prints per file: SAME <path> | DIFF <path> <where> | ERROR <path> <message>.
#   SAME = tree text is base text with "# frozen_string_literal: true\n\n" inserted after a leading
#   shebang line and leading encoding comments (where RuboCop puts it); base has no
#   frozen_string_literal magic comment; Prism trees of base and tree are equal once locations, the
#   NEWLINE flag and the FROZEN/MUTABLE flags of string nodes are dropped; magic comments equal apart
#   from the added one; __END__ data equal.
# freeze prints SAME/EXPLAINED/DIFF/ERROR: both sides carry the magic comment; trees equal after
#   rewriting every `<frozen string literal>.freeze` (no arguments, no block, no `&.`) to the literal.
#
# mutate prints one line per finding: FIND <path>:<line> <kind> <detail>, then "MUTATE <n> findings".
# A "literal value" is a node Prism marks frozen in the tree file (StringNode, InterpolatedStringNode
# without interpolation, __FILE__). Flow-insensitive, conservative "may hold a literal value":
#   - the literal itself; a local / ivar / cvar / gvar / constant ever assigned (=, ||=, &&=, parameter
#     default, multiple assignment from an array literal) something that may hold one; if/unless/
#     ternary/case/and/or/parentheses/begin yielding one; identity calls on one (to_s, to_str, itself,
#     presence, freeze, -@, then/tap/yield_self without changing the value); a call of a method of the
#     same file whose result may be one (implicit tail value or `return`);
#   - an element of an array/hash literal holding one, read by [] / first / last / fetch / dig /
#     values_at / sample / min / max, or as a block parameter of each/map/select/... on it.
# Kinds:
#   mutator   - a String-mutating method called on such a value (MUTATORS);
#   buffer    - such a value handed to an API that writes into its argument (StringIO.new/open,
#               CSV.generate, Builder target:, io.read/readpartial/read_nonblock/sysread/recv(n, buf));
#   param     - such a value passed (by position or keyword) to a method that some file of <all_list>
#               defines with that parameter mutated (name-based: any receiver);
#   return    - a method of a listed file that may return a literal value is the receiver of a mutator
#               anywhere in <all_list> (name-based: `x.<name> << y`, `<name>.gsub!(...)`).
require "prism"
require "set"

MUTATORS = %i[
  << concat prepend insert replace clear force_encoding encode! unicode_normalize! scrub! setbyte
  []= slice! squeeze! strip! lstrip! rstrip! chomp! chop! sub! gsub! tr! tr_s! delete! delete_prefix!
  delete_suffix! upcase! downcase! capitalize! swapcase! succ! next! reverse! bytesplice append_as_bytes
].to_set.freeze
IDENTITY = %i[to_s to_str itself presence freeze -@ then tap yield_self].to_set.freeze
ELEMENT = %i[[] first last fetch dig values_at sample min max find detect].to_set.freeze
ITERATORS = %i[each each_with_index each_with_object map flat_map collect select filter reject find detect
               each_slice each_cons sort_by min_by max_by group_by partition sum inject reduce].to_set.freeze
BUFFER_NEW = { "StringIO" => %i[new open], "CSV" => %i[generate generate_line] }.freeze
BUFFER_READ = %i[read readpartial read_nonblock sysread pread recv recvfrom].to_set.freeze
NEWLINE = Prism::NodeFlags::NEWLINE
STRING_FLAG_NODES = [Prism::StringNode, Prism::InterpolatedStringNode, Prism::SourceFileNode].freeze
MAGIC = "# frozen_string_literal: true\n"
# Flags the magic comment sets on string nodes (FROZEN/MUTABLE and the node's STATIC_LITERAL).
STRING_MASK = {
  Prism::StringNode => Prism::StringFlags::FROZEN | Prism::StringFlags::MUTABLE | Prism::NodeFlags::STATIC_LITERAL,
  Prism::SourceFileNode => Prism::StringFlags::FROZEN | Prism::StringFlags::MUTABLE | Prism::NodeFlags::STATIC_LITERAL,
  Prism::InterpolatedStringNode => Prism::InterpolatedStringNodeFlags::FROZEN | Prism::InterpolatedStringNodeFlags::MUTABLE |
                                   Prism::NodeFlags::STATIC_LITERAL
}.freeze

def parse!(src, path)
  res = Prism.parse(src, filepath: path)
  raise "parse error: #{res.errors.first.message}" unless res.errors.empty?

  res
end

def plain(node, mask_string_flags)
  return node.map { |x| plain(x, mask_string_flags) } if node.is_a?(Array)
  return node unless node.is_a?(Prism::Node)

  out = { t: node.class.name.split("::").last }
  node.class.fields.each do |f|
    next if f.is_a?(Prism::Reflection::LocationField) || f.is_a?(Prism::Reflection::OptionalLocationField)

    v = node.send(f.name)
    out[f.name] =
      case f
      when Prism::Reflection::FlagsField
        fl = node.send(:flags) & ~NEWLINE
        fl &= ~STRING_MASK[node.class] if mask_string_flags && STRING_MASK.key?(node.class)
        # STATIC_LITERAL of an array/hash follows its elements (compared on their own)
        fl &= ~Prism::NodeFlags::STATIC_LITERAL if mask_string_flags
        fl
      when Prism::Reflection::StringField then [v.encoding.name, v.bytes]
      when Prism::Reflection::FloatField then [v].pack("G").bytes
      else plain(v, mask_string_flags)
      end
  end
  out
end

# Magic comments Ruby honours: those before the first token (a later one is an ordinary comment).
def magic(res)
  first = res.value.statements.body.first&.location&.start_offset || Float::INFINITY
  res.magic_comments.select { |c| c.key_loc.start_offset < first }.map { |c| [c.key, c.value] }
end
def data(res) = res.data_loc&.slice

def expected_tree_text(base)
  lines = base.lines
  i = 0
  i += 1 if lines[0]&.start_with?("#!")
  i += 1 while lines[i]&.match?(/\A#.*\b(en)?coding\s*[:=]/i)
  (lines[0...i] + [MAGIC, "\n"] + lines[i..]).join
end

def first_diff(a, b, path = "")
  return nil if a == b
  return "#{path}: #{a.inspect[0, 80]} <> #{b.inspect[0, 80]}" unless a.class == b.class && (a.is_a?(Hash) || a.is_a?(Array))
  return "#{path}: size #{a.size} <> #{b.size}" if a.is_a?(Array) && a.size != b.size

  keys = a.is_a?(Hash) ? (a.keys | b.keys) : (0...a.size).to_a
  keys.each do |k|
    d = first_diff(a[k], b[k], "#{path}/#{a.is_a?(Hash) ? a[:t] : ''}.#{k}")
    return d if d
  end
  nil
end

def shape(base_dir, tree_dir, list)
  File.readlines(list, chomp: true).reject(&:empty?).each do |rel|
    bsrc = File.binread(File.join(base_dir, rel))
    tsrc = File.binread(File.join(tree_dir, rel))
    b = parse!(bsrc, rel)
    t = parse!(tsrc, rel)
    why =
      if magic(b).any? { |k, _| k == "frozen_string_literal" } then "base already has a frozen_string_literal magic comment"
      elsif tsrc != expected_tree_text(bsrc) then "text is not base + magic comment and blank line at the top"
      elsif magic(t).sort != (magic(b) + [["frozen_string_literal", "true"]]).sort then "magic comments"
      elsif data(b) != data(t) then "__END__ data"
      else first_diff(plain(b.value, true), plain(t.value, true))
      end
    puts why ? "DIFF #{rel} #{why}" : "SAME #{rel}"
  rescue StandardError => e
    puts "ERROR #{rel} #{e.class}: #{e.message.lines.first&.strip}"
  end
end

def strip_freeze(obj)
  case obj
  when Array then obj.map { |x| strip_freeze(x) }
  when Hash
    h = obj.to_h { |k, v| [k, k == :t ? v : strip_freeze(v)] }
    r = h[:receiver]
    if h[:t] == "CallNode" && h[:name] == :freeze && h[:arguments].nil? && h[:block].nil? &&
       (h[:flags] & Prism::CallNodeFlags::SAFE_NAVIGATION).zero? && r.is_a?(Hash) &&
       STRING_FLAG_NODES.map { |c| c.name.split("::").last }.include?(r[:t]) &&
       (r[:flags] & (r[:t] == "InterpolatedStringNode" ? Prism::InterpolatedStringNodeFlags::FROZEN : Prism::StringFlags::FROZEN)) != 0
      r
    else
      h
    end
  else obj
  end
end

def freeze_cmd(base_dir, tree_dir, list)
  File.readlines(list, chomp: true).reject(&:empty?).each do |rel|
    b = parse!(File.binread(File.join(base_dir, rel)), rel)
    t = parse!(File.binread(File.join(tree_dir, rel)), rel)
    fsl = ->(r) { magic(r).include?(["frozen_string_literal", "true"]) }
    pb = plain(b.value, false)
    pt = plain(t.value, false)
    v =
      if !fsl.(b) || !fsl.(t) then "DIFF #{rel} magic comment missing on one side"
      elsif magic(b) != magic(t) || data(b) != data(t) then "DIFF #{rel} magic comments / __END__"
      elsif pb == pt then "SAME #{rel}"
      elsif (d = first_diff(strip_freeze(pb), strip_freeze(pt))) then "DIFF #{rel} #{d}"
      else "EXPLAINED #{rel} Style/RedundantFreeze"
      end
    puts v
  rescue StandardError => e
    puts "ERROR #{rel} #{e.class}: #{e.message.lines.first&.strip}"
  end
end

# ---- mutate ------------------------------------------------------------------------------------
class Scan
  attr_reader :findings

  def initialize(path, res, param_mutators, all_returning)
    @path = path
    @root = res.value
    @param_mutators = param_mutators
    @all_returning = all_returning
    @findings = []
    @tainted = Set.new # [:lvar, scope_id, name] / [:ivar, name] / [:const, name] / [:gvar, name] / [:cvar, name] / [:meth, name]
    @containers = Set.new
  end

  def literal?(n)
    STRING_FLAG_NODES.any? { |c| n.is_a?(c) } && n.respond_to?(:frozen?) && n.frozen?
  end

  def returning_methods = @tainted.select { |k| k[0] == :meth }.map(&:last)

  def run
    loop do
      before = [@tainted.size, @containers.size]
      walk(@root, :top) { |n, scope| propagate(n, scope) }
      break if before == [@tainted.size, @containers.size]
    end
    walk(@root, :top) { |n, scope| sinks(n, scope) }
    self
  end

  def walk(node, scope, &blk)
    return unless node.is_a?(Prism::Node)

    yield node, scope
    inner = case node
            when Prism::DefNode, Prism::ClassNode, Prism::ModuleNode, Prism::SingletonClassNode then node.node_id
            else scope
            end
    node.compact_child_nodes.each { |c| walk(c, inner, &blk) }
  end

  def key(n, scope)
    case n
    when Prism::LocalVariableReadNode, Prism::LocalVariableWriteNode, Prism::LocalVariableOrWriteNode,
         Prism::LocalVariableAndWriteNode, Prism::LocalVariableTargetNode, Prism::OptionalParameterNode,
         Prism::OptionalKeywordParameterNode, Prism::RequiredParameterNode
      [:lvar, scope, n.name]
    when Prism::InstanceVariableReadNode, Prism::InstanceVariableWriteNode, Prism::InstanceVariableOrWriteNode,
         Prism::InstanceVariableAndWriteNode, Prism::InstanceVariableTargetNode
      [:ivar, n.name]
    when Prism::ClassVariableReadNode, Prism::ClassVariableWriteNode, Prism::ClassVariableOrWriteNode,
         Prism::ClassVariableTargetNode
      [:cvar, n.name]
    when Prism::GlobalVariableReadNode, Prism::GlobalVariableWriteNode, Prism::GlobalVariableOrWriteNode,
         Prism::GlobalVariableTargetNode
      [:gvar, n.name]
    when Prism::ConstantReadNode, Prism::ConstantWriteNode, Prism::ConstantOrWriteNode, Prism::ConstantTargetNode
      [:const, n.name]
    when Prism::ConstantPathNode, Prism::ConstantPathTargetNode then [:const, n.name]
    end
  end

  def may_lit?(n, scope)
    case n
    when nil then false
    when Prism::StringNode, Prism::InterpolatedStringNode, Prism::SourceFileNode then literal?(n)
    when Prism::ParenthesesNode, Prism::BeginNode then may_lit?(n.is_a?(Prism::BeginNode) ? n.statements : n.body, scope)
    when Prism::StatementsNode then may_lit?(n.body.last, scope)
    when Prism::IfNode then may_lit?(n.statements, scope) || may_lit?(n.subsequent, scope)
    when Prism::UnlessNode then may_lit?(n.statements, scope) || may_lit?(n.else_clause, scope)
    when Prism::ElseNode then may_lit?(n.statements, scope)
    when Prism::CaseNode, Prism::CaseMatchNode
      n.conditions.any? { |w| may_lit?(w.statements, scope) } || may_lit?(n.else_clause, scope)
    when Prism::OrNode, Prism::AndNode then may_lit?(n.left, scope) || may_lit?(n.right, scope)
    when Prism::LocalVariableWriteNode, Prism::InstanceVariableWriteNode, Prism::ConstantWriteNode,
         Prism::LocalVariableOrWriteNode, Prism::InstanceVariableOrWriteNode
      may_lit?(n.value, scope) || @tainted.include?(key(n, scope))
    when Prism::CallNode
      if n.receiver.nil? && n.arguments.nil? && @tainted.include?([:meth, n.name]) then true
      elsif n.receiver.is_a?(Prism::SelfNode) && @tainted.include?([:meth, n.name]) then true
      elsif IDENTITY.include?(n.name) && n.receiver then may_lit?(n.receiver, scope)
      elsif ELEMENT.include?(n.name) && n.receiver then container?(n.receiver, scope)
      else false
      end
    else
      (k = key(n, scope)) ? @tainted.include?(k) : false
    end
  end

  def container?(n, scope)
    case n
    when Prism::ArrayNode then n.elements.any? { |e| may_lit?(e, scope) || container?(e, scope) }
    when Prism::HashNode, Prism::KeywordHashNode
      n.elements.any? { |e| e.is_a?(Prism::AssocNode) && (may_lit?(e.value, scope) || container?(e.value, scope)) }
    when Prism::ParenthesesNode then container?(n.body, scope)
    when Prism::StatementsNode then container?(n.body.last, scope)
    when Prism::CallNode
      %i[freeze dup to_a values keys compact uniq flatten].include?(n.name) && n.receiver && container?(n.receiver, scope)
    else
      (k = key(n, scope)) ? @containers.include?(k) : false
    end
  end

  def taint(k) = k && @tainted.add(k)

  def propagate(n, scope)
    case n
    when Prism::LocalVariableWriteNode, Prism::LocalVariableOrWriteNode, Prism::LocalVariableAndWriteNode,
         Prism::InstanceVariableWriteNode, Prism::InstanceVariableOrWriteNode, Prism::InstanceVariableAndWriteNode,
         Prism::ClassVariableWriteNode, Prism::ClassVariableOrWriteNode, Prism::GlobalVariableWriteNode,
         Prism::GlobalVariableOrWriteNode, Prism::ConstantWriteNode, Prism::ConstantOrWriteNode,
         Prism::OptionalParameterNode, Prism::OptionalKeywordParameterNode
      taint(key(n, scope)) if may_lit?(n.value, scope)
      @containers.add(key(n, scope)) if container?(n.value, scope)
    when Prism::ConstantPathWriteNode
      taint([:const, n.target.name]) if may_lit?(n.value, scope)
      @containers.add([:const, n.target.name]) if container?(n.value, scope)
    when Prism::MultiWriteNode
      vals = n.value.is_a?(Prism::ArrayNode) ? n.value.elements : []
      n.lefts.each_with_index do |t, i|
        taint(key(t, scope)) if vals[i] && may_lit?(vals[i], scope)
      end
    when Prism::DefNode
      body_lit = may_lit?(n.body, scope_of_def(n)) || returns_lit?(n.body, scope_of_def(n))
      taint([:meth, n.name]) if body_lit
    when Prism::CallNode
      bparams = n.block.is_a?(Prism::BlockNode) && n.block.parameters.is_a?(Prism::BlockParametersNode) &&
                n.block.parameters.parameters ? n.block.parameters.parameters.requireds : []
      first_arg = n.arguments&.arguments&.first
      # memo object: each_with_object("") { |x, memo| }, inject("") { |memo, x| }; tap/then on a literal
      taint(key(bparams[1], scope)) if n.name == :each_with_object && bparams[1] && may_lit?(first_arg, scope)
      taint(key(bparams[0], scope)) if %i[inject reduce].include?(n.name) && bparams[0] && may_lit?(first_arg, scope)
      taint(key(bparams[0], scope)) if %i[tap then yield_self].include?(n.name) && bparams[0] && n.receiver &&
                                       may_lit?(n.receiver, scope)
      if n.block.is_a?(Prism::BlockNode) && ITERATORS.include?(n.name) && n.receiver && container?(n.receiver, scope)
        params = n.block.parameters&.parameters
        (params ? params.requireds : []).each { |p| taint(key(p, scope)) if p.is_a?(Prism::RequiredParameterNode) }
      end
    end
  end

  def scope_of_def(d) = d.node_id

  def returns_lit?(node, scope)
    found = false
    walk_same_def(node) { |x| found ||= x.is_a?(Prism::ReturnNode) && x.arguments && may_lit?(x.arguments.arguments.last, scope) }
    found
  end

  def walk_same_def(node, &blk)
    return unless node.is_a?(Prism::Node)

    yield node
    node.compact_child_nodes.each { |c| walk_same_def(c, &blk) unless c.is_a?(Prism::DefNode) }
  end

  def find(n, kind, detail) = @findings << "FIND #{@path}:#{n.location.start_line} #{kind} #{detail}"

  def sinks(n, scope)
    return unless n.is_a?(Prism::CallNode)

    args = n.arguments&.arguments || []
    if MUTATORS.include?(n.name) && n.receiver && may_lit?(n.receiver, scope)
      find(n, "mutator", "#{n.receiver.slice[0, 60]}.#{n.name}")
    end
    rname = n.receiver.respond_to?(:name) ? n.receiver.name.to_s : nil
    if rname && BUFFER_NEW[rname]&.include?(n.name) && args.first && may_lit?(args.first, scope)
      find(n, "buffer", "#{rname}.#{n.name}(#{args.first.slice[0, 40]})")
    end
    if BUFFER_READ.include?(n.name) && args[1] && may_lit?(args[1], scope)
      find(n, "buffer", "#{n.name}(_, #{args[1].slice[0, 40]})")
    end
    args.each do |a|
      next unless a.is_a?(Prism::KeywordHashNode)

      a.elements.each do |e|
        next unless e.is_a?(Prism::AssocNode) && e.key.is_a?(Prism::SymbolNode)

        find(n, "buffer", "target: #{e.value.slice[0, 40]}") if e.key.unescaped == "target" && may_lit?(e.value, scope)
        (@param_mutators[[n.name, e.key.unescaped.to_sym]] || []).each do |where|
          find(n, "param", "#{n.name}(#{e.key.unescaped}: #{e.value.slice[0, 40]}) mutated in #{where}") if may_lit?(e.value, scope)
        end
      end
    end
    args.each_with_index do |a, i|
      (@param_mutators[[n.name, i]] || []).each do |where|
        find(n, "param", "#{n.name}(arg #{i}: #{a.slice[0, 40]}) mutated in #{where}") if may_lit?(a, scope)
      end
    end
  end
end

def param_mutators(paths)
  out = Hash.new { |h, k| h[k] = [] }
  paths.each do |rel|
    res = Prism.parse_file(rel)
    next unless res.errors.empty?

    stack = [res.value]
    until stack.empty?
      node = stack.pop
      stack.concat(node.compact_child_nodes)
      next unless node.is_a?(Prism::DefNode) && node.parameters

      pos = {}
      (node.parameters.requireds + node.parameters.optionals).each_with_index { |p, i| pos[p.name] = i if p.respond_to?(:name) }
      kw = node.parameters.keywords.to_h { |p| [p.name, p.name] }
      inner = [node.body].compact
      until inner.empty?
        x = inner.pop
        next if x.is_a?(Prism::DefNode)

        inner.concat(x.compact_child_nodes)
        next unless x.is_a?(Prism::CallNode) && MUTATORS.include?(x.name) && x.receiver.is_a?(Prism::LocalVariableReadNode)

        nm = x.receiver.name
        out[[node.name, pos[nm]]] << "#{rel}:#{x.location.start_line}" if pos.key?(nm)
        out[[node.name, kw[nm]]] << "#{rel}:#{x.location.start_line}" if kw.key?(nm)
      end
    end
  end
  out.transform_values(&:uniq)
end

def returning_receivers(paths, names)
  hits = []
  paths.each do |rel|
    res = Prism.parse_file(rel)
    next unless res.errors.empty?

    stack = [res.value]
    until stack.empty?
      node = stack.pop
      stack.concat(node.compact_child_nodes)
      next unless node.is_a?(Prism::CallNode) && MUTATORS.include?(node.name)

      r = node.receiver
      r = r.receiver while r.is_a?(Prism::CallNode) && IDENTITY.include?(r.name) && r.receiver
      next unless r.is_a?(Prism::CallNode) && names.key?(r.name)

      hits << "FIND #{rel}:#{node.location.start_line} return #{r.name} (may return a literal of #{names[r.name].join(', ')}) .#{node.name}"
    end
  end
  hits
end

def mutate(tree_dir, list, all_list)
  Dir.chdir(tree_dir)
  files = File.readlines(list, chomp: true).reject(&:empty?)
  all = File.readlines(all_list, chomp: true).reject(&:empty?)
  pm = param_mutators(all)
  findings = []
  returning = Hash.new { |h, k| h[k] = [] }
  files.each do |rel|
    res = parse!(File.binread(rel), rel)
    unless magic(res).include?(["frozen_string_literal", "true"])
      findings << "FIND #{rel}:1 file has no frozen_string_literal: true magic comment"
      next
    end
    s = Scan.new(rel, res, pm, nil).run
    findings.concat(s.findings)
    s.returning_methods.each { |m| returning[m] << rel }
  rescue StandardError => e
    findings << "FIND #{rel}:1 error #{e.class}: #{e.message.lines.first&.strip}"
  end
  findings.concat(returning_receivers(all, returning))
  findings.uniq.each { |f| puts f }
  puts "MUTATE #{findings.uniq.size} findings"
end

case ARGV[0]
when "shape" then shape(*ARGV[1, 3])
when "freeze" then freeze_cmd(*ARGV[1, 3])
when "mutate" then mutate(*ARGV[1, 3])
else abort "usage: r3_frozen.rb shape|freeze <base> <tree> <list> | mutate <tree> <list> <all_list>"
end
