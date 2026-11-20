# frozen_string_literal: true

# Test driver for fork-updates-r5, run by r5_tests_gate.sh inside the bin/ci-local image, from the
# root of a `git archive HEAD` copy (never the clone itself):
#   ruby r5_tests.rb <r5_config.json> <dir with BASE versions of the app files> <out dir>
#
# 1. tree:  the char + fix spec files of r5_config.json, against the tree's app code: every file has
#           examples, every example passed, none pending, no error outside examples;
# 2. BASE:  the same files against BASE's app code (the app files swapped in): every char example
#           passed (they pin today's behaviour), every fix file has >= 1 failed example (the fix
#           changes behaviour), no error outside examples;
# 3. mutants: each mutant of r5_config.json applied alone to the tree's app code (its `old` text must
#           occur exactly once) - its spec files must have >= 1 failed example and no error outside
#           examples (killed by an assertion, not by a load error).
# Prints "R5 TREE PASS <n> examples", "R5 BASE PASS <char> char / <fix> fix failing",
# "R5 MUTANTS PASS <k>/<k> killed", or "FAIL: ..." lines; exits 1 on any failure.
require "json"
require "fileutils"

cfg = JSON.parse(File.read(ARGV.fetch(0)))
base_dir = ARGV.fetch(1)
out_dir = ARGV.fetch(2)
FileUtils.mkdir_p(out_dir)
fails = []
char = cfg.fetch("char_specs")
fix = cfg.fetch("fix_specs")
specs = char + fix

abort "FAIL: SPEC_OPTS is set" if ENV.key?("SPEC_OPTS")
abort "FAIL: .rspec-local present" if File.exist?(".rspec-local")

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
  puts "R5 TREE PASS #{tree['examples'].size} examples" if fails.empty?
end

# 2. BASE app code -----------------------------------------------------------------------------------
saved = cfg.fetch("app_files").to_h { |f| [f, File.read(f)] }
cfg.fetch("app_files").each { |f| FileUtils.cp(File.join(base_dir, f), f) }
base = rspec(specs, "#{out_dir}/base.json")
saved.each { |f, s| File.write(f, s) }
if base["error"]
  fails << "BASE run: #{base['error']}"
else
  fails << "BASE run: #{outside(base)} errors outside examples" unless outside(base).zero?
  files = by_file(base)
  char.each do |f|
    fails << "#{f}: no examples ran on BASE" if files.fetch(f, []).empty?
    files.fetch(f, []).reject { |e| e["status"] == "passed" }.each do |e|
      fails << "#{f}: characterization example #{e['full_description']} is #{e['status']} on BASE"
    end
  end
  red = fix.count do |f|
    n = files.fetch(f, []).count { |e| e["status"] == "failed" }
    fails << "#{f}: no example fails on BASE (the fix must change behaviour)" if n.zero?
    n.positive?
  end
  nchar = char.sum { |f| files.fetch(f, []).size }
  puts "R5 BASE PASS #{nchar} char / #{red} fix failing" if fails.none? { |x| x.include?("BASE") }
end
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
puts "R5 MUTANTS PASS #{killed}/#{muts.size} killed" if killed == muts.size

fails.each { |f| puts "FAIL: #{f}" }
exit(fails.empty? ? 0 : 1)
