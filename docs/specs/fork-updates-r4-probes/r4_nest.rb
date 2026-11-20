# frozen_string_literal: true

# Static checker for fork-updates-r4 (Style/ClassAndModuleChildren: `class A::B` -> nested
# `module A; class B`).
#
#   ruby r4_nest.rb shape <base_dir> <tree_dir> <list>   per file: SAME | DIFF <where> | ERROR
#   ruby r4_nest.rb refs  <base_dir> <tree_dir> <list>   JSON of every unqualified constant reference
#   ruby r4_nest.rb defs  <dir>...                       JSON list of every constant path defined there
#
# shape: both files are parsed with Prism; on both sides every `module P` whose body is exactly one
#   class/module definition with a plain name N is merged into that definition named P::N (the
#   nested form written back as the compact one); the trees are then compared without locations and
#   the NEWLINE flag (literals exact: string bytes and encoding, IEEE bytes of floats); magic comments,
#   __END__ and the list of all comments (text stripped, in order - so no `# rubocop:disable` or any
#   other comment added, dropped or changed) must be equal. SAME = the files differ only in nesting
#   and layout.
# refs: for each file, walks base and tree in the same order (shape SAME guarantees it) and lists
#   every constant reference whose head is unqualified (`X`, the `X` of `X::Y`; not `::X`, not the
#   name of a class/module being defined), including superclass expressions, with the lexical chain
#   of definitions around it on each side: [["class", "Agents::Auth0Controller"], ["sclass", "self"]]
#   for base and [["module", "Agents"], ["class", "Auth0Controller"], ...] for the tree.
#   r4_resolve.rb evaluates the name inside both chains in the booted app and compares the results.
#   Each file also lists "consts": the full paths of the classes/modules it defines (both sides).
# defs: every class/module/constant definition under the dirs (recursively, *.rb) as a full lexical path
#   (`module MessageApis; module Slack; X = 1` -> MessageApis::Slack::X); r4_resolve.rb uses it as
#   the static list of names a plugin load can add under a namespace.
require "json"
require "prism"

NEWLINE = Prism::NodeFlags::NEWLINE

def parse!(path)
  res = Prism.parse_file(path)
  raise "parse error: #{res.errors.first.message}" unless res.errors.empty?

  res
end

def plain(node)
  return node.map { |x| plain(x) } if node.is_a?(Array)
  return node unless node.is_a?(Prism::Node)

  out = { t: node.class.name.split("::").last }
  node.class.fields.each do |f|
    next if f.is_a?(Prism::Reflection::LocationField) || f.is_a?(Prism::Reflection::OptionalLocationField)

    v = node.send(f.name)
    out[f.name] =
      case f
      when Prism::Reflection::FlagsField then node.send(:flags) & ~NEWLINE
      when Prism::Reflection::StringField then [v.encoding.name, v.bytes]
      when Prism::Reflection::FloatField then [v].pack("G").bytes
      else plain(v)
      end
  end
  out
end

DEFS = %w[ClassNode ModuleNode].freeze

# module P; <class|module> N ...; end  ==>  <class|module> P::N ...
def merge(obj)
  case obj
  when Array then obj.map { |x| merge(x) }
  when Hash
    h = obj.to_h { |k, v| [k, k == :t ? v : merge(v)] }
    body = h[:t] == "ModuleNode" && h[:body].is_a?(Hash) && h[:body][:t] == "StatementsNode" ? h[:body][:body] : nil
    inner = body&.size == 1 ? body.first : nil
    if inner && DEFS.include?(inner[:t]) && relative?(inner[:constant_path]) && h[:locals].empty?
      inner.merge(constant_path: prepend(h[:constant_path], inner[:constant_path]))
    else
      h
    end
  else obj
  end
end

# A::B written relative to the scope it is in (no leading ::).
def relative?(path)
  return true if path[:t] == "ConstantReadNode"

  path[:t] == "ConstantPathNode" && !path[:parent].nil? && relative?(path[:parent])
end

# Prefix outer path P to a relative path: N -> P::N, X::N -> (P::X)::N.
def prepend(outer, path)
  return { t: "ConstantPathNode", parent: outer, name: path[:name] } if path[:t] == "ConstantReadNode"

  { t: "ConstantPathNode", parent: prepend(outer, path[:parent]), name: path[:name] }
end

def magic(res) = res.magic_comments.map { |c| [c.key, c.value] }

def comments(res) = res.comments.map { |c| c.slice.strip }

def first_diff(a, b, path = "")
  return nil if a == b
  return "#{path}: #{a.inspect[0, 80]} <> #{b.inspect[0, 80]}" unless a.class == b.class && (a.is_a?(Hash) || a.is_a?(Array))
  return "#{path}: size #{a.size} <> #{b.size}" if a.is_a?(Array) && a.size != b.size

  (a.is_a?(Hash) ? (a.keys | b.keys) : (0...a.size)).each do |k|
    d = first_diff(a[k], b[k], "#{path}/#{a.is_a?(Hash) ? a[:t] : ''}.#{k}")
    return d if d
  end
  nil
end

def shape(base_dir, tree_dir, list)
  File.readlines(list, chomp: true).reject(&:empty?).each do |rel|
    b = parse!(File.join(base_dir, rel))
    t = parse!(File.join(tree_dir, rel))
    why =
      if magic(b) != magic(t) then "magic comments"
      elsif b.data_loc&.slice != t.data_loc&.slice then "__END__ data"
      elsif comments(b) != comments(t)
        bc = comments(b)
        tc = comments(t)
        i = (0...[bc.size, tc.size].max).find { |k| bc[k] != tc[k] }
        "comments: #{bc[i].inspect[0, 60]} <> #{tc[i].inspect[0, 60]}"
      else first_diff(merge(plain(b.value)), merge(plain(t.value)))
      end
    puts why ? "DIFF #{rel} #{why}" : "SAME #{rel}"
  rescue StandardError => e
    puts "ERROR #{rel} #{e.class}: #{e.message.lines.first&.strip}"
  end
end

# Collect [name, chain] for every unqualified constant reference, in traversal order.
def collect(node, chain, out)
  case node
  when Prism::ClassNode, Prism::ModuleNode
    collect(node.superclass, chain, out) if node.is_a?(Prism::ClassNode) && node.superclass
    kind = node.is_a?(Prism::ClassNode) ? "class" : "module"
    inner = chain + [[kind, node.constant_path.slice]]
    collect(node.body, inner, out) if node.body
    return
  when Prism::SingletonClassNode
    collect(node.expression, chain, out)
    inner = chain + [["sclass", node.expression.slice]]
    collect(node.body, inner, out) if node.body
    return
  when Prism::ConstantReadNode
    out << [node.name.to_s, chain]
    return
  when Prism::ConstantPathNode
    head = node
    head = head.parent while head.is_a?(Prism::ConstantPathNode) && head.parent
    if head.is_a?(Prism::ConstantPathNode) # ::X, absolute
      return
    end

    collect(head, chain, out)
    return
  end
  node&.compact_child_nodes&.each { |c| collect(c, chain, out) }
end

# Full path of the innermost class/module of a chain (nil inside `class << x`).
def full(chain)
  chain.reduce("") do |acc, (kind, path)|
    return nil if kind == "sclass"

    path.start_with?("::") ? path[2..] : [acc, path].reject(&:empty?).join("::")
  end
end

def consts(node, chain, out)
  case node
  when Prism::ClassNode, Prism::ModuleNode
    inner = chain + [[node.is_a?(Prism::ClassNode) ? "class" : "module", node.constant_path.slice]]
    out << full(inner) if full(inner)
    consts(node.body, inner, out) if node.body
    return
  when Prism::SingletonClassNode
    return
  when Prism::ConstantWriteNode, Prism::ConstantOrWriteNode
    out << full(chain + [["const", node.name.to_s]]) if full(chain)
  when Prism::ConstantPathWriteNode, Prism::ConstantPathOrWriteNode
    out << full(chain + [["const", node.target.slice]]) if full(chain)
  end
  node&.compact_child_nodes&.each { |c| consts(c, chain, out) }
end

def defs(dirs)
  out = []
  dirs.flat_map { |d| Dir.glob(File.join(d, "**", "*.rb")) }.sort.each { |f| consts(parse!(f).value, [], out) }
  puts JSON.generate(out.uniq.sort)
end

def refs(base_dir, tree_dir, list)
  files = File.readlines(list, chomp: true).reject(&:empty?).map do |rel|
    b = []
    t = []
    collect(parse!(File.join(base_dir, rel)).value, [], b)
    collect(parse!(File.join(tree_dir, rel)).value, [], t)
    raise "#{rel}: #{b.size} references at BASE, #{t.size} in the tree" unless b.size == t.size

    pairs = b.zip(t).map do |(bn, bc), (tn, tc)|
      raise "#{rel}: reference #{bn} at BASE is #{tn} in the tree" unless bn == tn

      { "name" => bn, "base" => bc, "tree" => tc }
    end
    cb = []
    ct = []
    consts(parse!(File.join(base_dir, rel)).value, [], cb)
    consts(parse!(File.join(tree_dir, rel)).value, [], ct)
    { "file" => rel, "refs" => pairs.uniq, "consts" => (cb | ct).sort }
  end
  puts JSON.generate(files)
end

case ARGV[0]
when "shape" then shape(*ARGV[1, 3])
when "refs" then refs(*ARGV[1, 3])
when "defs" then defs(ARGV.drop(1).tap { |d| abort "defs: no dir" if d.empty? })
else abort "usage: r4_nest.rb shape|refs <base_dir> <tree_dir> <list> | defs <dir>"
end
