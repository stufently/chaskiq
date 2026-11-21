# frozen_string_literal: true

# Test driver for fix-cleanup-3, run by fxd_tests_gate.sh inside the bin/ci-local image, from the
# root of a `git archive HEAD` copy (never the clone itself):
#   ruby fxd_tests.rb <fxd_config.json> <dir with BASE versions of the app files> <out dir>
#
# 1. tree:  the fix spec files of fxd_config.json against the tree's app code: every file has
#           examples, every example passed, none pending, no error outside examples;
# 2. BASE:  the same files against BASE's app code (the app files swapped in): every fix file has
#           >= 1 example that failed on an expectation (RSpec::Expectations::*NotMetError) whose
#           message matches the file's base_reason (the defect itself, not a crash or a typo); no
#           error outside examples;
# 3. mutants: each mutant applied alone to the tree's app code (its `old` text must occur exactly
#           once) - its spec files must have >= 1 failed example and no error outside examples.
# Prints "FXD TREE PASS <n> examples", "FXD BASE PASS <k> fix failing for the defect",
# "FXD MUTANTS PASS <m>/<m> killed", or "FAIL: ..." lines; exits 1 on any failure.
require "json"
require "fileutils"

cfg = JSON.parse(File.read(ARGV.fetch(0)))
base_dir = ARGV.fetch(1)
out_dir = ARGV.fetch(2)
FileUtils.mkdir_p(out_dir)
fails = []
fix = cfg.fetch("fix_specs")
specs = fix.map { |f| f.fetch("file") }

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
  puts "FXD TREE PASS #{tree['examples'].size} examples" if fails.empty?
end

# 2. BASE app code -----------------------------------------------------------------------------------
saved = cfg.fetch("app_files").to_h { |f| [f, File.read(f)] }
cfg.fetch("app_files").each { |f| FileUtils.cp(File.join(base_dir, f), f) }
base = rspec(specs, "#{out_dir}/base.json")
saved.each { |f, s| File.write(f, s) }
nbase = fails.size
if base["error"]
  fails << "BASE run: #{base['error']}"
else
  fails << "BASE run: #{outside(base)} errors outside examples" unless outside(base).zero?
  files = by_file(base)
  red = fix.count do |spec|
    f = spec.fetch("file")
    reason = Regexp.new(spec.fetch("base_reason"))
    failed = files.fetch(f, []).select { |e| e["status"] == "failed" }
    right = failed.select do |e|
      ex = e["exception"] || {}
      ex["class"].to_s.start_with?("RSpec::Expectations::") && ex["message"].to_s.match?(reason)
    end
    if failed.empty?
      fails << "#{f}: no example fails on BASE (the fix must change behaviour)"
    elsif right.empty?
      got = failed.map { |e| "#{e.dig('exception', 'class')}: #{e.dig('exception', 'message').to_s[0, 160]}" }
      fails << "#{f}: fails on BASE for the wrong reason (need an expectation failure matching " \
               "#{reason.source.inspect}): #{got.first(2).join(' | ')}"
    end
    right.any?
  end
  puts "FXD BASE PASS #{red} fix failing for the defect" if fails.size == nbase
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
puts "FXD MUTANTS PASS #{killed}/#{muts.size} killed" if killed == muts.size

fails.each { |f| puts "FAIL: #{f}" }
exit(fails.empty? ? 0 : 1)
