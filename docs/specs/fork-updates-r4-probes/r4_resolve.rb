# frozen_string_literal: true

# Run with `bin/rails runner` (test env); eager-loads the app first:
#   bin/rails runner r4_resolve.rb resolve  <refs.json> <defs.json>
#   bin/rails runner r4_resolve.rb ancestry <refs.json> <out.json>
#
# resolve: for every reference of `r4_nest.rb refs`, evaluates the bare name inside the lexical chain
#   of BASE (`class Agents::X` ... `Name` ... `end`) and inside the chain of the tree (`module Agents`,
#   `class X` ...), at the top level, and requires the same result: the same object, or the same
#   exception class (a NameError on both sides). A `module A` over a class A raises TypeError on the
#   tree side only - also a mismatch. Self-test first: a constant shadowed in the new namespace and a
#   class turned into `module` must both be reported, a plain reference must not.
#   Static check: for every namespace the tree chain adds to the lexical scope (Agents, then
#   Agents::X, ...), a constant `<namespace>::<Name>` listed in defs.json (definitions found in the
#   source by `r4_nest.rb defs`, loaded or not) must exist and be the object BASE resolves the name
#   to - else a later load could shadow the name.
#   Then the plugin load of config/initializers/before_start.rb (ChaskiqBoot.plugin_autoloader ->
#   Plugin.save_all_plugins: rewrites a plugin's files into app/services/message_apis/<plugin>/ and
#   require_dependency's each) is reproduced without writing: every *.rb under
#   app/services/message_apis/*/ is `load`ed again; then every reference is checked a second time.
# ancestry: after the same eager load and plugin load, dumps for every class/module the changed files
#   define ("consts" of refs.json) its superclass, ancestors and singleton-class ancestors, by name,
#   to <out.json>; resolve_gate_r4.sh runs it once in a BASE checkout and once in the tree and
#   requires identical dumps (a superclass or mixin chosen at definition time that changed).
# Prints "R4 RESOLVE PASS <n> references, 2 passes" / "R4 ANCESTRY DUMP <n> constants", or one
# "FAIL:" line per mismatch and exits 1.
require "json"

mode, refs_path, extra = ARGV
abort "usage: r4_resolve.rb resolve|ancestry <refs.json> <defs.json|out.json>" unless
  %w[resolve ancestry].include?(mode) && refs_path && extra

Rails.application.eager_load! # every app constant loaded, and a `module A` over a class fails here
puts "R4 EAGER LOAD OK"

def load_plugins
  files = Dir.glob(Rails.root.join("app/services/message_apis/*/**/*.rb").to_s).sort
  files.each { |f| load f }
  files.size
end

def snippet(chain, name)
  opens = chain.map { |kind, path| kind == "sclass" ? "class << #{path}" : "#{kind} #{path}" }
  (opens + [name] + ["end"] * chain.size).join("\n")
end

def evaluate(chain, name)
  [:ok, TOPLEVEL_BINDING.eval(snippet(chain, name))]
rescue ScriptError, StandardError => e
  [:error, e.class]
end

def same?(a, b) = a[0] == b[0] && (a[0] == :ok ? a[1].equal?(b[1]) : a[1] == b[1])

def show(r) = r[0] == :ok ? r[1].inspect[0, 80] : "raises #{r[1]}"

# Lexical scopes of a chain as full paths, outermost first; stops at `class << x`.
def crefs(chain)
  out = []
  chain.each do |kind, path|
    break if kind == "sclass"

    out << (path.start_with?("::") ? path[2..] : [out.last, path].compact.join("::"))
  end
  out
end

def lookup(path)
  path.split("::").reduce(Object) do |m, n|
    raise NameError, path unless m.is_a?(Module) && m.const_defined?(n, false)

    m.const_get(n, false)
  end
end

def mname(m) = m.name || m.inspect.gsub(/0x\h+/, "0x")

files = JSON.parse(File.read(refs_path))

if mode == "ancestry"
  plugins = load_plugins
  dump = {}
  files.flat_map { |f| f["consts"] }.uniq.sort.each do |c|
    v = begin
      lookup(c)
    rescue NameError => e
      dump[c] = "missing (#{e.class})"
      next
    end
    dump[c] =
      if v.is_a?(Module)
        { "kind" => v.class.name, "superclass" => v.is_a?(Class) ? v.superclass&.then { mname(_1) } : nil,
          "ancestors" => v.ancestors.map { mname(_1) },
          "singleton" => v.singleton_class.ancestors.map { mname(_1) } }
      else
        { "kind" => "value", "class" => v.class.name }
      end
  end
  File.write(extra, JSON.pretty_generate(dump))
  puts "R4 PLUGIN LOAD OK #{plugins} files"
  puts "R4 ANCESTRY DUMP #{dump.size} constants"
  exit 0
end

defs = JSON.parse(File.read(extra)).to_h { |d| [d, true] }
fails = []
TOPLEVEL_BINDING.eval(<<~RUBY)
  module R4ProbeNs; R4ProbeC = :inner; class Leaf; end; end
  R4ProbeC = :top
  class R4ProbeKlass; class Leaf; end; end
RUBY
selftest = [
  [[["class", "R4ProbeNs::Leaf"]], [["module", "R4ProbeNs"], ["class", "Leaf"]], "R4ProbeC", false],
  [[["class", "R4ProbeKlass::Leaf"]], [["module", "R4ProbeKlass"], ["class", "Leaf"]], "String", false],
  [[["class", "R4ProbeNs::Leaf"]], [["module", "R4ProbeNs"], ["class", "Leaf"]], "String", true]
]
selftest.each do |base, tree, name, want|
  got = same?(evaluate(base, name), evaluate(tree, name))
  fails << "self-test #{name} in #{tree.inspect}: same=#{got}, expected #{want}" unless got == want
end
st = [["module", "R4ProbeNs"], ["class", "Leaf"]]
unless (crefs(st) - crefs([["class", "R4ProbeNs::Leaf"]])) == ["R4ProbeNs"] && lookup("R4ProbeNs::R4ProbeC") == :inner
  fails << "self-test: static shadow check does not see R4ProbeNs::R4ProbeC"
end

def check(files, fails, label)
  n = 0
  files.each do |file|
    file["refs"].each do |ref|
      n += 1
      a = evaluate(ref["base"], ref["name"])
      b = evaluate(ref["tree"], ref["name"])
      next if same?(a, b)

      fails << "#{label}#{file['file']}: #{ref['name']} in #{ref['tree'].map(&:last).join(' > ')}: " \
               "BASE #{show(a)}, tree #{show(b)}"
    end
  end
  n
end

n = check(files, fails, "")
shadow = 0
files.each do |file|
  file["refs"].each do |ref|
    (crefs(ref["tree"]) - crefs(ref["base"])).each do |ns|
      hit = "#{ns}::#{ref['name']}"
      next unless defs[hit]

      shadow += 1
      a = evaluate(ref["base"], ref["name"])
      obj = begin
        lookup(hit)
      rescue NameError
        :missing
      end
      next if a[0] == :ok && a[1].equal?(obj)

      fails << "#{file['file']}: #{ref['name']} could resolve to #{hit} (defined in the source) after nesting; " \
               "BASE #{show(a)}"
    end
  end
end
plugins = load_plugins
puts "R4 PLUGIN LOAD OK #{plugins} files"
n2 = check(files, fails, "after plugin load: ")
fails.each { |f| puts "FAIL: #{f}" }
exit 1 unless fails.empty? && n == n2
puts "R4 STATIC SHADOW CHECK #{shadow} candidates"
puts "R4 RESOLVE PASS #{n} references, 2 passes"
