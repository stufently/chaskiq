# frozen_string_literal: true

# Semantic-equivalence helper for fork-updates-r10c (run by r10c_tests_gate.sh inside the CI image).
# Usage: ruby r10c_iseq.rb <base_dir> <tree_dir> <relative paths...>
# For every path prints one line:
#   SAME <path>                 YARV bytecode of BASE and tree is identical
#   DIFF <path> <where>         bytecode differs (first differing node)
#   LINES <path> <where>        line-sensitive file (see below) whose line numbers moved
#   NEWWARN <path> <message>    `ruby -wc` prints a warning for the tree file that BASE did not print
#   ERROR <path> <message>      file does not compile
# Bytecode is compared without what only says WHERE code is: line numbers, line events, node ids,
# code locations and file paths. Everything else (instructions, operands, call flags, locals,
# params, catch tables, nested blocks/methods/classes, magic comments) must be equal; literals are
# compared by class and exact representation (String: encoding, bytes, frozen; Float: IEEE bytes,
# so 0.0 <> -0.0; Symbol: encoding and bytes; Regexp: source, options, encoding; Range, Array,
# Hash: element by element, in order). A file whose code can observe its own line numbers
# (`__LINE__`, `caller`, `caller_locations`, `source_location`, `eval`, `*_eval`/`*_exec` with a
# string) is "line-sensitive": for it line numbers are compared too.
require "open3"
require "ripper"

# Normalized-bytecode comparison of two versions of a Ruby file.
module R10cIseq
  HEADER = "YARVInstructionSequence/SimpleDataFormat"
  WHERE_KEYS = %i[code_location node_id node_ids].freeze
  LINE_IDENTS = %w[caller caller_locations source_location eval].freeze
  STRING_EVALS = %w[class_eval module_eval instance_eval class_exec module_exec instance_exec].freeze
  STRING_START = %i[on_tstring_beg on_heredoc_beg].freeze
  SKIP = %i[on_sp on_lparen].freeze

  module_function

  def norm(obj, keep_lines)
    case obj
    when Array then norm_array(obj, keep_lines)
    when Hash then [:H, obj.map { |k, v| [norm(k, keep_lines), norm(v, keep_lines)] }]
    else canon(obj)
    end
  end

  def norm_array(obj, keep_lines)
    return norm_iseq(obj, keep_lines) if obj[0] == HEADER

    [:A, obj.map { |x| norm(x, keep_lines) }]
  end

  # Exact representation of a literal: Ruby == would call "a" (US-ASCII) and "a" (UTF-8), or
  # 0.0 and -0.0, equal.
  CANON = {
    String => ->(o) { [:S, o.encoding.name, o.bytes, o.frozen?] },
    Symbol => ->(o) { [:Y, o.name.encoding.name, o.name.bytes] },
    Float => ->(o) { [:F, [o].pack("G").bytes] },
    Regexp => ->(o) { [:R, canon(o.source), o.options, o.encoding.name] },
    Range => ->(o) { [:G, canon(o.begin), canon(o.end), o.exclude_end?] }
  }.freeze

  def canon(obj)
    rule = CANON.find { |klass, _| obj.is_a?(klass) }
    rule ? rule.last.call(obj) : [obj.class.name, obj.inspect]
  end

  # [label, type, locals, params, catch table, misc, body] of one iseq, locations dropped.
  def norm_iseq(obj, keep_lines)
    misc = obj[4].except(*WHERE_KEYS).sort.to_h
    [obj[5], obj[9], norm(obj[10], keep_lines), norm(norm_params(obj[11]), keep_lines),
     norm(obj[12], keep_lines), norm(misc, keep_lines), norm_body(obj[13], keep_lines)]
  end

  def norm_params(params)
    params.is_a?(Hash) ? params.except(:node_id) : params
  end

  # Line numbers are bare Integers between instructions; line events only mark them.
  def norm_body(body, keep_lines)
    kept = keep_lines ? body : body.reject { |x| x.is_a?(Integer) || x == :RUBY_EVENT_LINE }
    kept.map { |x| norm(x, keep_lines) }
  end

  def iseq(path, keep_lines: false)
    norm(RubyVM::InstructionSequence.compile(File.read(path), "f.rb", "f.rb", 1).to_a, keep_lines)
  end

  def line_sensitive?(path)
    toks = Ripper.lex(File.read(path)).map { |(_, type, text, _)| [type, text] }
    toks.each_with_index.any? { |(type, text), i| line_token?(type, text) || string_eval?(toks, i) }
  end

  def line_token?(type, text)
    (type == :on_kw && text == "__LINE__") || (type == :on_ident && LINE_IDENTS.include?(text))
  end

  def string_eval?(toks, idx)
    return false unless toks[idx][0] == :on_ident && STRING_EVALS.include?(toks[idx][1])

    nxt = toks[(idx + 1)..].find { |(type, _)| SKIP.none?(type) }
    nxt && STRING_START.include?(nxt[0])
  end

  def first_diff(left, right, where = "")
    return mismatch(left, right, where) unless left.is_a?(Array) && right.is_a?(Array)

    [left.size, right.size].min.times do |i|
      d = first_diff(left[i], right[i], "#{where}[#{i}]")
      return d if d
    end
    "#{where}: length #{left.size} <> #{right.size}" unless left.size == right.size
  end

  def mismatch(left, right, where)
    "#{where}: #{left.inspect[0, 120]} <> #{right.inspect[0, 120]}" unless left == right
  end

  def warnings(path)
    _out, err, _st = Open3.capture3("ruby", "-wc", path)
    err.lines.filter_map { |l| l[/warning: .*/]&.strip }.uniq
  end

  def check(base, tree, rel)
    d = first_diff(iseq(base), iseq(tree))
    puts(d ? "DIFF #{rel} #{d}" : "SAME #{rel}")
    check_lines(base, tree, rel) unless d
    new_warnings(base, tree).each { |w| puts "NEWWARN #{rel} #{w}" }
  rescue SyntaxError, StandardError => e
    puts "ERROR #{rel} #{e.class}: #{e.message.lines.first&.strip}"
  end

  def new_warnings(base, tree)
    warnings(tree) - warnings(base)
  end

  def check_lines(base, tree, rel)
    return unless line_sensitive?(base) || line_sensitive?(tree)

    d = first_diff(iseq(base, keep_lines: true), iseq(tree, keep_lines: true))
    puts "LINES #{rel} #{d}" if d
  end
end

base_dir, tree_dir, *paths = ARGV
paths.each { |rel| R10cIseq.check(File.join(base_dir, rel), File.join(tree_dir, rel), rel) }
