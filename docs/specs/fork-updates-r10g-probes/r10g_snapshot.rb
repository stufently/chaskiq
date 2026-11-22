# frozen_string_literal: true

# Snapshot probe for fork-updates-r10g (run by r10g_snapshot_gate.sh inside the CI image, plain Ruby, no gems).
# Usage: ruby r10g_snapshot.rb <r10g_config.json> <presenter.rb> <out_dir>
# Loads the given MessageApis::UiCatalog::Presenter file (BASE copy or the tree's) and, for every entry of
# "snapshots" (name, kind, ctx_keys, ctx), calls Presenter.configure_hook(kind:, ctx:) and writes
# <out_dir>/<name>.json = JSON.pretty_generate({case, kind, ctx_keys, ctx, result}) + "\n".
# ctx_keys "symbol": ctx with symbol keys at every level (JSON.parse symbolize_names); "string": string keys.
# Checks (each failure is a spec defect when run on BASE):
#   - every result round-trips through JSON (JSON.parse(JSON.generate(r), symbolize_names: true) == r):
#     only symbol keys, JSON values; so a snapshot pins the whole hash, key order included;
#   - COVERAGE: every hash with an :action key anywhere in any result (a catalog button, list item, option,
#     input with an action) is, exactly, the ctx field of some symbol-keyed snapshot (the element as the
#     messenger submits it).
# Prints "R10G SNAPSHOTS <n> cases, <m> action elements covered" or "FAIL: ..." lines; exit 1 on any failure.
require "json"
require "fileutils"

cfg_path, presenter, out_dir = ARGV
abort "usage: r10g_snapshot.rb <config> <presenter.rb> <out_dir>" unless out_dir

module MessageApis; end
load File.expand_path(presenter)
P = MessageApis::UiCatalog::Presenter
FAILS = []
cases = JSON.parse(File.read(cfg_path)).fetch("snapshots")
FAILS << "config lists no snapshots" if cases.empty?
names = cases.map { |c| c.fetch("name") }
FAILS << "duplicate snapshot names" if names.uniq.size != names.size

def stringify(obj)
  case obj
  when Hash then obj.to_h { |k, v| [k.to_s, stringify(v)] }
  when Array then obj.map { |v| stringify(v) }
  else obj
  end
end

def action_elements(obj, acc)
  case obj
  when Hash
    acc << obj if obj.key?(:action)
    obj.each_value { |v| action_elements(v, acc) }
  when Array then obj.each { |v| action_elements(v, acc) }
  end
  acc
end

FileUtils.mkdir_p(out_dir)
fields = []
elements = []
cases.each do |c|
  name = c.fetch("name")
  FAILS << "#{name}: name must match [a-z0-9_]+" unless name.match?(/\A[a-z0-9_]+\z/)
  sym_ctx = JSON.parse(JSON.generate(c.fetch("ctx")), symbolize_names: true)
  ctx = case c.fetch("ctx_keys")
        when "symbol" then sym_ctx
        when "string" then stringify(sym_ctx)
        else FAILS << "#{name}: ctx_keys must be symbol or string"
             next
        end
  fields << sym_ctx[:field] if c["ctx_keys"] == "symbol" && sym_ctx[:field]
  begin
    result = P.configure_hook(kind: c.fetch("kind"), ctx: ctx)
  rescue StandardError => e
    FAILS << "#{name}: configure_hook raised #{e.class}: #{e.message}"
    next
  end
  if JSON.parse(JSON.generate(result), symbolize_names: true) != result
    FAILS << "#{name}: result does not round-trip through JSON (non-symbol key or non-JSON value)"
  end
  action_elements(result, elements)
  doc = { "case" => name, "kind" => c["kind"], "ctx_keys" => c["ctx_keys"], "ctx" => c["ctx"], "result" => result }
  File.write(File.join(out_dir, "#{name}.json"), "#{JSON.pretty_generate(doc)}\n")
end
uniq = elements.uniq
uniq.each do |el|
  next if fields.include?(el)

  FAILS << "COVERAGE: no symbol-keyed snapshot submits the action element #{JSON.generate(el)[0, 160]}"
end
FAILS.each { |f| puts "FAIL: #{f}" }
exit 1 unless FAILS.empty?
puts "R10G SNAPSHOTS #{cases.size} cases, #{uniq.size} action elements covered"
