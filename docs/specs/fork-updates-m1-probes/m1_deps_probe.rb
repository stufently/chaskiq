# frozen_string_literal: true

# Probe for fork-updates-m1, packages A and C (Ruby side). Reads Gemfile and
# Gemfile.lock of the current directory. Hard requirements fail the probe. Every Snyk
# floor that is not met must be named (gem name as a word) in the note of AC-001 in
# report.json at the repo root; otherwise the probe fails.
require "bundler"
require "json"

lock = Bundler::LockfileParser.new(File.read("Gemfile.lock"))
gemfile = File.read("Gemfile")
fails = []
specs = lock.specs.group_by(&:name)

def ver(specs, name)
  s = specs[name]&.first
  s && Gem::Version.new(s.version.to_s)
end

def src(specs, name)
  specs[name]&.first&.source
end

git_remotes = lock.sources.select { |s| s.is_a?(Bundler::Source::Git) }.map { |s| s.uri.to_s }
%w[jules-w2/globalize frederikspang/roadie-rails].each do |dead|
  fails << "Gemfile.lock still has GIT source #{dead} (404 upstream)" if git_remotes.any? { |u| u.include?(dead) }
end
fails << "Gemfile still references jules-w2/globalize" if gemfile.include?("jules-w2/globalize")
fails << "Gemfile still references frederikspang/roadie-rails" if gemfile.include?("frederikspang/roadie-rails")
fails << "Gemfile must declare gem \"globalize\", \"~> 7.1\"" unless gemfile.match?(/^gem "globalize", "~> 7\.1"/)

rubygems = ->(name) { src(specs, name).is_a?(Bundler::Source::Rubygems) }
g = ver(specs, "globalize")
fails << "globalize must be >= 7.1.3, < 8 from rubygems (got #{g.inspect})" unless g && g >= Gem::Version.new("7.1.3") && g < Gem::Version.new("8") && rubygems.call("globalize")
r = ver(specs, "roadie-rails")
fails << "roadie-rails must be >= 3.4.0 from rubygems (got #{r.inspect})" unless r && r >= Gem::Version.new("3.4.0") && rubygems.call("roadie-rails")
rk = ver(specs, "rack")
fails << "rack must be >= 2.2.25 and < 3 (got #{rk.inspect})" unless rk && rk >= Gem::Version.new("2.2.25") && rk < Gem::Version.new("3")
ra = ver(specs, "rack-attack")
fails << "rack-attack must be >= 6.8.0 (got #{ra.inspect})" unless ra && ra >= Gem::Version.new("6.8.0")
fails << "rack-attack must be a direct dependency" unless lock.dependencies.key?("rack-attack")
rails = ver(specs, "rails")
fails << "rails must stay on 7.2.1.x in this milestone (got #{rails.inspect})" unless rails && rails >= Gem::Version.new("7.2.1") && rails < Gem::Version.new("7.2.2")
fails << "lockfile BUNDLED WITH must stay 2.4.10 (got #{lock.bundler_version})" unless lock.bundler_version.to_s == "2.4.10"

floors = {
  "rails" => "7.2.1.1", "aws-sdk-s3" => "1.208.0", "omniauth-oauth2" => "1.9.0", "faraday" => "2.14.1",
  "twilio-ruby" => "5.67.0", "opensearch-ruby" => "3.1.0", "google-cloud-dialogflow" => "1.7.0",
  "anycable-rails" => "1.5.5", "uri" => "0.12.5", "jsbundling-rails" => "1.2.2", "propshaft" => "0.8.0",
  "devise" => "4.9.4", "graphiql-rails" => "1.10.0", "devise_invitable" => "2.0.9", "doorkeeper" => "5.6.0",
  "sidekiq" => "7.2.0", "aws-sdk-rails" => "3.9.1", "net-http" => "0.4.0", "rack-cors" => "2.0.0",
  "dotenv-rails" => "3.0.0", "cypress-on-rails" => "1.17.0", "rspec-rails" => "6.0.4",
  "factory_bot_rails" => "6.4.4", "rubocop" => "1.66.0", "rubocop-performance" => "1.20.0",
  "rubocop-rails" => "2.22.0", "rubocop-rspec" => "2.25.0"
}
note = begin
  report = JSON.parse(File.read("report.json"))
  Array(report["criteria"]).find { |c| c["id"] == "AC-001" }&.fetch("note", "").to_s
rescue Errno::ENOENT, JSON::ParserError
  ""
end
puts "Snyk floors (unmet ones must be named in report.json AC-001 note with the failing specs):"
floors.each do |name, floor|
  v = ver(specs, name)
  state = v.nil? ? "absent" : (v >= Gem::Version.new(floor) ? "met" : "UNMET")
  puts format("  %-26s floor %-9s locked %-10s %s", name, floor, v.to_s, state)
  next unless state == "UNMET"

  fails << "Snyk floor #{name} >= #{floor} not met and not named in report.json AC-001 note" unless note.match?(/(?<![\w-])#{Regexp.escape(name)}(?![\w-])/)
end

if fails.empty?
  puts "DEPS PROBE PASS"
else
  puts fails
  exit 1
end
