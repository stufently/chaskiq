# frozen_string_literal: true

# Test driver for fork-updates-r10i, run by r10i_tests_gate.sh inside the bin/ci-local image, from the
# root of a `git archive HEAD` copy (never the clone itself):
#   ruby r10i_tests.rb <r10i_config.json> <dir with BASE versions of the app files> <out dir>
#
# char_specs of the config pin today's behaviour against the snapshot fixtures (new_files of the config,
# generated from BASE by r10i_snapshot.rb and checked by r10i_snapshot_gate.sh).
# 1. tree:  the char specs against the tree's code: every file has examples, every example passed, none
#           pending, no error outside examples; every snapshot of the config has a passed example whose
#           full description ends with " <snapshot name>";
# 2. BASE:  the same files against BASE's code (app_files swapped for their BASE versions; the fixtures
#           stay): every example passed, no error outside examples;
# 3. mutants: each mutant of the config applied alone to the tree's code (its `old` text must occur
#           exactly once) - its spec files must have >= 1 failed example and no error outside examples
#           (killed by an assertion, not by a load error).
# Prints "R10I TREE PASS <n> examples, <s> snapshots", "R10I BASE PASS <n> examples",
# "R10I MUTANTS PASS <k>/<k> killed", or "FAIL: ..." lines; exits 1 on any failure.
require "json"
require "fileutils"

cfg = JSON.parse(File.read(ARGV.fetch(0)))
base_dir = ARGV.fetch(1)
out_dir = ARGV.fetch(2)
FileUtils.mkdir_p(out_dir)
fails = []
specs = cfg.fetch("char_specs")
snaps = cfg.fetch("snapshots").map { |s| s.fetch("name") }

abort "FAIL: SPEC_OPTS is set" if ENV.key?("SPEC_OPTS")
abort "FAIL: .rspec-local present" if File.exist?(".rspec-local")
abort "FAIL: no spec files in the config" if specs.empty?

def rspec(files, out)
  FileUtils.rm_f(out)
  system("bundle", "exec", "rspec", "--options", ".rspec", "--format", "json", "--out", out, *files,
         out: File::NULL, err: "#{out}.err")
  JSON.parse(File.read(out))
rescue Errno::ENOENT, JSON::ParserError => e
  { "error" => "#{e.class}: no rspec json (#{File.read("#{out}.err")[-300..] rescue ''})" }
end

def by_file(res)
  res.fetch("examples", []).group_by { |e| e["file_path"].sub(%r{\A\./}, "") }
end

def outside(res) = res.dig("summary", "errors_outside_of_examples_count")

def check_run(res, specs, where, fails)
  if res["error"]
    fails << "#{where} run: #{res['error']}"
    return false
  end
  fails << "#{where} run: #{outside(res)} errors outside examples" unless outside(res).zero?
  files = by_file(res)
  specs.each do |f|
    ex = files.fetch(f, [])
    fails << "#{f}: no examples ran on #{where}" if ex.empty?
    ex.reject { |e| e["status"] == "passed" }.each do |e|
      fails << "#{f}: #{e['full_description']} is #{e['status']} on #{where}"
    end
  end
  true
end

# 1. tree --------------------------------------------------------------------------------------------
n0 = fails.size
tree = rspec(specs, "#{out_dir}/tree.json")
if check_run(tree, specs, "the tree", fails)
  passed = tree["examples"].select { |e| e["status"] == "passed" }.map { |e| e["full_description"] }
  snaps.each do |s|
    fails << "snapshot #{s}: no passed example whose description ends with \" #{s}\"" \
      if passed.none? { |d| d.end_with?(" #{s}") }
  end
  puts "R10I TREE PASS #{tree['examples'].size} examples, #{snaps.size} snapshots" if fails.size == n0
end

# 2. BASE code ---------------------------------------------------------------------------------------
n0 = fails.size
saved = cfg.fetch("app_files").to_h { |f| [f, File.read(f)] }
cfg.fetch("app_files").each { |f| FileUtils.cp(File.join(base_dir, f), f) }
base = rspec(specs, "#{out_dir}/base.json")
saved.each { |f, s| File.write(f, s) }
puts "R10I BASE PASS #{base['examples'].size} examples" if check_run(base, specs, "BASE", fails) && fails.size == n0
saved.each { |f, s| fails << "#{f}: not restored after BASE run" unless File.read(f) == s }

# 3. mutants -----------------------------------------------------------------------------------------
killed = 0
muts = cfg.fetch("mutants")
muts.each do |m|
  src = File.read(m["file"])
  if src.scan(m["old"]).size != 1
    fails << "#{m['id']}: mutant text occurs #{src.scan(m['old']).size} times in #{m['file']} (must be 1)"
    next
  end
  File.write(m["file"], src.sub(m["old"]) { m["new"] })
  res = rspec(m["specs"], "#{out_dir}/#{m['id']}.json")
  File.write(m["file"], src)
  failed = res.dig("summary", "failure_count").to_i
  if res["error"] || !outside(res).zero? || failed.zero?
    fails << "#{m['id']} #{m['file']}: survived (failures #{failed}, outside #{outside(res).inspect}" \
             "#{res['error'] ? ", #{res['error']}" : ''})"
  else
    killed += 1
    puts "KILLED #{m['id']} (#{failed} failing)"
  end
end
puts "R10I MUTANTS PASS #{killed}/#{muts.size} killed" if killed == muts.size && !muts.empty?

fails.each { |f| puts "FAIL: #{f}" }
exit(fails.empty? ? 0 : 1)
