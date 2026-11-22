# frozen_string_literal: true

# Test driver for fork-updates-r10h2, run by r10h2_tests_gate.sh inside the bin/ci-local image, from the
# root of a `git archive HEAD` copy (never the clone itself):
#   ruby r10h2_tests.rb <r10h2_config.json> <dir with BASE versions of the app files> <out dir>
#
# Spec files of the config: char_specs and check_specs (existing files; every example pins today's
# behaviour), mixed_specs (examples
# whose full description contains " renamed " exercise a new name; the others pin today's behaviour
# through the old names), fix_specs (each changes behaviour).
# 1. tree:  all those files against the tree's code: every file has examples, every example passed,
#           none pending, no error outside examples;
# 2. BASE:  the same files against BASE's code (app_files swapped for their BASE versions, new_files
#           removed): every characterization example passed; every "renamed" example failed and each
#           mixed file has >= 1 of each kind; every fix file has >= 1 failed example; no error outside
#           examples;
# 3. mutants: each mutant of the config applied alone to the tree's code (its `old` text must occur
#           exactly once) - its spec files must have >= 1 failed example and no error outside examples
#           (killed by an assertion, not by a load error).
# 4. golden (config "golden"): during step 2 (BASE code in place) the coordinator's generator
#           (golden.generator, an rspec file next to the config) runs every case of golden.cases and
#           writes the outcomes; the result must be byte for byte golden.fixture of the tree. Every case
#           name must have an example of golden.spec (full description ending in " <name>") that
#           passed on the tree and on BASE.
# Prints "R10H2 TREE PASS <n> examples", "R10H2 BASE PASS <c> char / <r> renamed failing / <f> fix failing",
# "R10H2 MUTANTS PASS <k>/<k> killed", "R10H2 GOLDEN PASS <n> cases", or "FAIL: ..." lines; exits 1 on any failure.
require "json"
require "fileutils"

TAG = "R10H2"

cfg = JSON.parse(File.read(ARGV.fetch(0)))
base_dir = ARGV.fetch(1)
out_dir = ARGV.fetch(2)
FileUtils.mkdir_p(out_dir)
fails = []
char = cfg.fetch("char_specs", []) + cfg.fetch("check_specs", [])
mixed = cfg.fetch("mixed_specs", [])
fix = cfg.fetch("fix_specs", [])
specs = char + mixed + fix
# The golden fixture is characterization: it stays in place for the BASE run.
new_files = cfg.fetch("new_files", []) - [cfg.dig("golden", "fixture")]

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

def renamed?(example) = example["full_description"].include?(" renamed ")

# 1. tree --------------------------------------------------------------------------------------------
tree = rspec(specs, "#{out_dir}/tree.json")
if tree["error"]
  fails << "tree run: #{tree['error']}"
else
  fails << "tree run: #{outside(tree)} errors outside examples" unless outside(tree).zero?
  files = by_file(tree)
  specs.each do |f|
    ex = files.fetch(f, [])
    fails << "#{f}: no examples ran" if ex.empty?
    ex.reject { |e| e["status"] == "passed" }.each do |e|
      fails << "#{f}: #{e['full_description']} is #{e['status']} on the tree"
    end
  end
  puts "R10H2 TREE PASS #{tree['examples'].size} examples" if fails.empty?
end

# 2. BASE code ---------------------------------------------------------------------------------------
saved = cfg.fetch("app_files").to_h { |f| [f, File.read(f)] }
saved_new = new_files.to_h { |f| [f, File.read(f)] }
cfg.fetch("app_files").each { |f| FileUtils.cp(File.join(base_dir, f), f) }
new_files.each { |f| File.delete(f) }
base = rspec(specs, "#{out_dir}/base.json")
golden_cfg = cfg["golden"]
golden_out = "#{out_dir}/golden.json"
if golden_cfg
  FileUtils.rm_f(golden_out)
  system({ "R10H_CASES" => File.expand_path(File.join("..", golden_cfg.fetch("cases"))),
           "R10H_GOLDEN_OUT" => File.expand_path(golden_out) },
         "bundle", "exec", "rspec", "--options", ".rspec", File.join("..", golden_cfg.fetch("generator")),
         out: "#{out_dir}/golden.out", err: "#{out_dir}/golden.err")
end
saved.merge(saved_new).each { |f, s| File.write(f, s) }
if base["error"]
  fails << "BASE run: #{base['error']}"
else
  fails << "BASE run: #{outside(base)} errors outside examples" unless outside(base).zero?
  files = by_file(base)
  nchar = 0
  nren = 0
  (char + mixed).each do |f|
    ex = files.fetch(f, [])
    fails << "#{f}: no examples ran on BASE" if ex.empty?
    old_ex, new_ex = mixed.include?(f) ? [ex.reject { |e| renamed?(e) }, ex.select { |e| renamed?(e) }] : [ex, []]
    if mixed.include?(f) && (old_ex.empty? || new_ex.empty?)
      fails << "#{f}: needs examples on the old names and \" renamed \" examples on the new names (BASE)"
    end
    old_ex.reject { |e| e["status"] == "passed" }.each do |e|
      fails << "#{f}: characterization example #{e['full_description']} is #{e['status']} on BASE"
    end
    new_ex.reject { |e| e["status"] == "failed" }.each do |e|
      fails << "#{f}: renamed example #{e['full_description']} is #{e['status']} on BASE (the new name must not exist there)"
    end
    nchar += old_ex.size
    nren += new_ex.count { |e| e["status"] == "failed" }
  end
  red = fix.count do |f|
    n = files.fetch(f, []).count { |e| e["status"] == "failed" }
    fails << "#{f}: no example fails on BASE (the fix must change behaviour)" if n.zero?
    n.positive?
  end
  puts "R10H2 BASE PASS #{nchar} char / #{nren} renamed failing / #{red} fix failing" if fails.none? { |x| x.include?("BASE") }
end
saved.merge(saved_new).each { |f, s| fails << "#{f}: not restored after BASE run" unless File.read(f) == s }

# 4. golden ------------------------------------------------------------------------------------------
if golden_cfg
  fixture = golden_cfg.fetch("fixture")
  if !File.exist?(golden_out)
    fails << "golden: the generator wrote nothing on BASE (#{File.read("#{out_dir}/golden.out")[-300..]})"
  elsif !File.exist?(fixture)
    fails << "golden: #{fixture} missing in the tree"
  elsif File.binread(golden_out) != File.binread(fixture)
    a = File.binread(golden_out)
    b = File.binread(fixture)
    at = (0...[a.size, b.size].min).find { |i| a[i] != b[i] } || [a.size, b.size].min
    fails << "golden: #{fixture} is not the generator's output on BASE (first difference at byte #{at})"
  else
    names = JSON.parse(File.read(fixture)).map { |c| c.fetch("name") }
    fails << "golden: case names are not unique" unless names.uniq.size == names.size
    spec = golden_cfg.fetch("spec")
    { "tree" => tree, "BASE" => base }.each do |side, res|
      ex = by_file(res).fetch(spec, [])
      names.each do |nm|
        hit = ex.select { |e| e["full_description"].end_with?(" #{nm}") }
        fails << "golden: #{side}: case #{nm.inspect} has no passed example in #{spec}" unless hit.any? { |e| e["status"] == "passed" }
      end
    end
    puts "#{TAG} GOLDEN PASS #{names.size} cases" if fails.none? { |x| x.start_with?("golden") }
  end
end

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
puts "R10H2 MUTANTS PASS #{killed}/#{muts.size} killed" if killed == muts.size

fails.each { |f| puts "FAIL: #{f}" }
exit(fails.empty? ? 0 : 1)
