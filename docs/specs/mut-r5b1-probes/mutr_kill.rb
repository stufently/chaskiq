# frozen_string_literal: true

# Kill driver for mut-r5b1, run by mutr_kill_gate.sh inside the bin/ci-local image, from the root
# of a `git archive HEAD` copy (never the clone itself):
#   ruby mutr_kill.rb <jobs.json> <patch dir> <out dir>
# jobs.json: [{"id", "file", "patch", "specs": [...], "test_added": "spec/..." or null}]
# 1. baseline: all specs of all jobs on the unmutated copy - no failed example (BASE pending ones
#    are allowed; AC-001 limits pending to the BASE list), no error outside examples;
# 2. each job alone: `git apply <patch>` (must apply and change the file), run its specs, restore the
#    file byte for byte. Killed = >= 1 failed example and no error outside examples (an assertion,
#    not a load error); with test_added - >= 1 failed example in that file. A run over RUN_LIMIT
#    seconds counts as not killed (the recorded specs must finish with the mutant applied).
# Prints "KILLED <id> ...", "SURVIVED <id> ..." lines and "MUTR KILL PASS <k>/<k> killed" or
# "FAIL: ..." lines; exits 1 on any failure.
require "json"
require "fileutils"

jobs = JSON.parse(File.read(ARGV.fetch(0)))
pdir = ARGV.fetch(1)
out = ARGV.fetch(2)
FileUtils.mkdir_p(out)
fails = []
abort "FAIL: SPEC_OPTS is set" if ENV.key?("SPEC_OPTS")
abort "FAIL: .rspec-local present" if File.exist?(".rspec-local")
ENV["GIT_CEILING_DIRECTORIES"] = File.dirname(Dir.pwd)

RUN_LIMIT = 300 # seconds per rspec run; a hang (e.g. a lock never taken) is not an assertion kill

def rspec(files, path)
  FileUtils.rm_f(path)
  system("timeout", "-k", "10", RUN_LIMIT.to_s, "bundle", "exec", "rspec", "--options", ".rspec", "--format", "json",
         "--out", path, *files, out: File::NULL, err: "#{path}.err")
  return { "error" => "rspec timed out after #{RUN_LIMIT}s" } if [124, 137].include?($?.exitstatus)

  JSON.parse(File.read(path))
rescue Errno::ENOENT, JSON::ParserError => e
  { "error" => "#{e.class}: no rspec json (#{File.read("#{path}.err")[-300..] rescue ''})" }
end

def outside(res) = res.dig("summary", "errors_outside_of_examples_count").to_i

all = jobs.flat_map { _1["specs"] }.uniq.sort
base = rspec(all, "#{out}/baseline.json")
if base["error"] || !outside(base).zero?
  fails << "baseline: #{base['error'] || "#{outside(base)} errors outside examples"}"
else
  base["examples"].select { _1["status"] == "failed" }.each do |e|
    fails << "baseline: #{e['file_path']} #{e['full_description']} is #{e['status']} without a mutant"
  end
  puts "MUTR BASELINE #{base['examples'].size} examples in #{all.size} files"
end
unless fails.empty?
  fails.each { puts "FAIL: #{_1}" }
  exit 1
end

killed = 0
jobs.each do |j|
  src = File.binread(j["file"])
  ok = system("git", "apply", File.join(pdir, j["patch"]), out: File::NULL, err: File::NULL)
  if !ok || File.binread(j["file"]) == src
    File.binwrite(j["file"], src)
    fails << "#{j['id']}: patch #{j['patch']} does not apply or does not change #{j['file']}"
    next
  end
  res = rspec(j["specs"], "#{out}/#{j['id']}.json")
  File.binwrite(j["file"], src)
  failed = res.fetch("examples", []).select { _1["status"] == "failed" }.map { _1["file_path"].sub(%r{\A\./}, "") }
  hit = j["test_added"] ? failed.include?(j["test_added"]) : !failed.empty?
  if res["error"] || !outside(res).zero? || !hit
    why = res["error"] || "failed #{failed.size} (in #{failed.uniq.first(3).join(', ')}), outside #{outside(res)}"
    puts "SURVIVED #{j['id']} #{j['file']}: #{why}"
    fails << "#{j['id']} #{j['file']}: not killed by an assertion#{j['test_added'] ? " in #{j['test_added']}" : ''} (#{why})"
  else
    killed += 1
    puts "KILLED #{j['id']} (#{failed.size} failing)"
  end
end
puts "MUTR KILL PASS #{killed}/#{jobs.size} killed" if killed == jobs.size
fails.each { puts "FAIL: #{_1}" }
exit(fails.empty? ? 0 : 1)
