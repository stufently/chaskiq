# frozen_string_literal: true

# Static guard for fork-updates-r6b (Lint/UnusedMethodArgument: unused positional argument x -> _x).
#
#   ruby r6b_guard.rb <base_dir> <tree_dir> <list>
#
# For every file of <list>, the method definitions of BASE and the tree are paired in order (same
# count, same names). In each pair the parameter lists must be equal except renames x -> _x of
# positional parameters (required, optional, rest, post); no keyword, block or other change. For
# every method with a rename:
#   - neither x nor _x is read, written or targeted anywhere in its body (blocks included, nested
#     defs excluded), and _x is not a parameter name at BASE;
#   - the body has no `super` without arguments (zsuper passes the current parameter values and,
#     for keywords, names), no `binding`, `eval`/`*_eval`/`*_exec` with a string, `local_variables`,
#     `__method__`, `method(...)`/`.parameters` introspection;
# and the file has no ERB/`binding` anywhere. Self-test first (each forbidden form must be caught).
# Prints "OK <file> <n renames>" per file or "BAD <file>: <why>"; "R6B GUARD PASS <files> files,
# <renames> renames" at the end; exits 1 on any BAD.
require "prism"

POSITIONAL = %i[requireds optionals rest posts].freeze
FORBIDDEN_CALLS = %w[binding eval instance_eval class_eval module_eval instance_exec class_exec
                     local_variables __method__ method parameters].freeze

def defs(node, out = [])
  return out unless node.is_a?(Prism::Node)

  out << node if node.is_a?(Prism::DefNode)
  node.compact_child_nodes.each { |c| defs(c, out) }
  out
end

def param_names(defn)
  p = defn.parameters
  return {} unless p

  out = {}
  POSITIONAL.each do |k|
    Array(p.public_send(k)).compact.each_with_index { |x, i| out[[k, i]] = x.respond_to?(:name) ? x.name : nil }
  end
  out[[:keywords]] = p.keywords.map(&:name)
  out[[:keyword_rest]] = p.keyword_rest&.then { |k| [k.class.name, k.respond_to?(:name) ? k.name : nil] }
  out[[:block]] = p.block&.name
  out
end

# Walk a method body without entering nested defs/classes/modules.
def walk(node, &blk)
  return unless node.is_a?(Prism::Node)

  yield node
  return if node.is_a?(Prism::DefNode) || node.is_a?(Prism::ClassNode) || node.is_a?(Prism::ModuleNode) ||
            node.is_a?(Prism::SingletonClassNode)

  node.compact_child_nodes.each { |c| walk(c, &blk) }
end

LOCAL_NODES = [Prism::LocalVariableReadNode, Prism::LocalVariableWriteNode, Prism::LocalVariableTargetNode,
               Prism::LocalVariableOperatorWriteNode, Prism::LocalVariableOrWriteNode,
               Prism::LocalVariableAndWriteNode, Prism::BlockParameterNode, Prism::RequiredParameterNode,
               Prism::OptionalParameterNode].freeze

def body_problems(defn, names)
  probs = []
  walk(defn.body) do |n|
    probs << "zsuper (`super` without arguments)" if n.is_a?(Prism::ForwardingSuperNode)
    if n.is_a?(Prism::CallNode) && FORBIDDEN_CALLS.include?(n.name.to_s)
      probs << "calls #{n.name}"
    end
    if LOCAL_NODES.any? { |k| n.is_a?(k) } && n.respond_to?(:name) && names.include?(n.name)
      probs << "uses #{n.name}"
    end
  end
  probs.uniq
end

def check(base_src, tree_src)
  b = Prism.parse(base_src)
  t = Prism.parse(tree_src)
  return ["parse error"] unless b.errors.empty? && t.errors.empty?
  return ["ERB or binding in the file"] if tree_src.match?(/\bERB\b|Erubi|\bbinding\b/)

  bd = defs(b.value)
  td = defs(t.value)
  return ["#{bd.size} defs at BASE, #{td.size} in the tree"] unless bd.size == td.size

  renames = 0
  probs = []
  bd.zip(td).each do |x, y|
    next probs << "def #{x.name} became #{y.name}" unless x.name == y.name

    bp = param_names(x)
    tp = param_names(y)
    next probs << "def #{x.name}: parameter shape changed" unless bp.keys == tp.keys

    changed = []
    bp.each do |k, v|
      next if v == tp[k]

      if POSITIONAL.include?(k.first) && v && tp[k] == :"_#{v}"
        changed << [v, tp[k]]
      else
        probs << "def #{x.name}: #{k.first} #{v.inspect} -> #{tp[k].inspect} (only positional x -> _x allowed)"
      end
    end
    next if changed.empty?

    renames += changed.size
    taken = bp.values.flatten.compact
    changed.each { |_, nn| probs << "def #{x.name}: #{nn} already a parameter at BASE" if taken.include?(nn) }
    names = changed.flatten
    body_problems(y, names).each { |pr| probs << "def #{y.name}: #{pr}" }
    body_problems(x, names).each { |pr| probs << "def #{x.name} at BASE: #{pr}" }
  end
  probs.empty? ? renames : probs
end

selftest = {
  "def f(a) = 1" => ["def f(_a) = 1", 1],
  "def f(a)\n  super\nend" => ["def f(_a)\n  super\nend", :bad],
  "def f(a)\n  binding\nend" => ["def f(_a)\n  binding\nend", :bad],
  "def f(a)\n  local_variables\nend" => ["def f(_a)\n  local_variables\nend", :bad],
  "def f(a)\n  method(__method__).parameters\nend" => ["def f(_a)\n  method(__method__).parameters\nend", :bad],
  "def f(a, k:) = 1" => ["def f(a, _k:) = 1", :bad],
  "def f(a)\n  _a = 2\nend" => ["def f(_a)\n  _a = 2\nend", :bad],
  "def f(a) = 1\n" => ["def g(_a) = 1\n", :bad]
}
st_fail = selftest.filter_map do |b, (t, want)|
  got = check(b, t)
  ok = want == :bad ? got.is_a?(Array) : got == want
  "self-test #{b.lines.first.strip.inspect}: got #{got.inspect}" unless ok
end

base_dir, tree_dir, list = ARGV
files = File.readlines(list, chomp: true).reject(&:empty?)
bad = st_fail.dup
total = 0
files.each do |rel|
  r = check(File.read(File.join(base_dir, rel)), File.read(File.join(tree_dir, rel)))
  if r.is_a?(Array)
    r.each { |pr| bad << "#{rel}: #{pr}" }
  else
    total += r
    puts "OK #{rel} #{r}"
  end
end
bad.each { |b| puts "BAD #{b}" }
exit 1 unless bad.empty?
puts "R6B GUARD PASS #{files.size} files, #{total} renames"
