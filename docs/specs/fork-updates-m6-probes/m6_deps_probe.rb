# frozen_string_literal: true

# Probe for fork-updates-m6 (Rails 8.1 upgrade), dependency side. Reads Gemfile and
# Gemfile.lock of the current directory and the lockfile of BASE (env M6_BASE, a commit).
# Hard requirements only; every failure is printed and the probe exits 1.
#   - rails 8.1.x >= 8.1.4.1, < 8.2, all rails frameworks on the same version;
#   - acts-as-taggable-on >= 13.0 from rubygems (the mbleigh git source is gone);
#   - Rails 8.1 companions: uri >= 1.0, mini_magick >= 5.1, ruby-vips >= 2.2.1;
#   - invariants of m1..m4 kept: rack 2.2.x (>= 2.2.25, < 3), rack-attack >= 6.8 direct,
#     globalize ~> 7.1 and roadie-rails >= 3.4 from rubygems, BUNDLED WITH and RUBY VERSION
#     unchanged, the Snyk floors of m1 still met;
#   - no new git sources; only gems of the allowed set changed version vs BASE.
require "bundler"
require "json"

base = ENV.fetch("M6_BASE") { abort "FAIL: M6_BASE (base commit) is required" }
lock = Bundler::LockfileParser.new(File.read("Gemfile.lock"))
base_text = IO.popen(["git", "show", "#{base}:Gemfile.lock"], &:read)
abort "FAIL: cannot read Gemfile.lock at #{base}" unless $?.success? && !base_text.empty?
base_lock = Bundler::LockfileParser.new(base_text)
gemfile = File.read("Gemfile")
fails = []
specs = lock.specs.group_by(&:name)
base_specs = base_lock.specs.group_by(&:name)

def ver(specs, name)
  s = specs[name]&.first
  s && Gem::Version.new(s.version.to_s)
end

rubygems = ->(name) { specs[name]&.first&.source.is_a?(Bundler::Source::Rubygems) }
v = ->(s) { Gem::Version.new(s) }

rails = ver(specs, "rails")
fails << "rails must be >= 8.1.4.1 and < 8.2 (got #{rails.inspect})" unless rails && rails >= v.("8.1.4.1") && rails < v.("8.2")
%w[actioncable actionmailbox actionmailer actionpack actiontext actionview activejob activemodel
   activerecord activestorage activesupport railties].each do |fw|
  fails << "#{fw} must equal rails #{rails} (got #{ver(specs, fw).inspect})" unless ver(specs, fw) == rails
end
fails << "Gemfile must declare rails ~> 8.1 (no exact 7.2 pin)" unless gemfile.match?(/^gem "rails", "~> 8\.1/)

t = ver(specs, "acts-as-taggable-on")
fails << "acts-as-taggable-on must be >= 13.0 from rubygems (got #{t.inspect})" unless t && t >= v.("13.0") && rubygems.call("acts-as-taggable-on")
fails << "Gemfile still declares acts-as-taggable-on from git" if gemfile.match?(/^gem "acts-as-taggable-on".*github:/)

{ "uri" => "1.0", "mini_magick" => "5.1", "ruby-vips" => "2.2.1" }.each do |name, floor|
  got = ver(specs, name)
  fails << "#{name} must be >= #{floor} (got #{got.inspect})" unless got && got >= v.(floor)
end

rk = ver(specs, "rack")
fails << "rack must stay 2.2.x >= 2.2.25 (got #{rk.inspect})" unless rk && rk >= v.("2.2.25") && rk < v.("3")
ra = ver(specs, "rack-attack")
fails << "rack-attack must be >= 6.8.0 and a direct dependency" unless ra && ra >= v.("6.8.0") && lock.dependencies.key?("rack-attack")
g = ver(specs, "globalize")
fails << "globalize must be >= 7.1.3, < 8 from rubygems (got #{g.inspect})" unless g && g >= v.("7.1.3") && g < v.("8") && rubygems.call("globalize")
r = ver(specs, "roadie-rails")
fails << "roadie-rails must be >= 3.4.0 from rubygems (got #{r.inspect})" unless r && r >= v.("3.4.0") && rubygems.call("roadie-rails")
fails << "BUNDLED WITH changed (#{base_lock.bundler_version} -> #{lock.bundler_version})" unless lock.bundler_version.to_s == base_lock.bundler_version.to_s
fails << "RUBY VERSION changed (#{base_lock.ruby_version} -> #{lock.ruby_version})" unless lock.ruby_version.to_s == base_lock.ruby_version.to_s

floors = {
  "aws-sdk-s3" => "1.208.0", "omniauth-oauth2" => "1.9.0", "faraday" => "2.14.1",
  "twilio-ruby" => "5.67.0", "opensearch-ruby" => "3.1.0", "google-cloud-dialogflow" => "1.7.0",
  "anycable-rails" => "1.5.5", "jsbundling-rails" => "1.2.2", "propshaft" => "0.8.0",
  "devise" => "4.9.4", "graphiql-rails" => "1.10.0", "devise_invitable" => "2.0.9", "doorkeeper" => "5.6.0",
  "sidekiq" => "7.2.0", "aws-sdk-rails" => "3.9.1", "net-http" => "0.4.0", "rack-cors" => "2.0.0",
  "dotenv-rails" => "3.0.0", "cypress-on-rails" => "1.17.0", "rspec-rails" => "6.0.4",
  "factory_bot_rails" => "6.4.4", "rubocop" => "1.66.0", "rubocop-performance" => "1.20.0",
  "rubocop-rails" => "2.22.0", "rubocop-rspec" => "2.25.0"
}
floors.each do |name, floor|
  got = ver(specs, name)
  fails << "Snyk floor #{name} >= #{floor} not met (got #{got.inspect})" unless got && got >= v.(floor)
end

git_remotes = ->(l) { l.sources.select { |s| s.is_a?(Bundler::Source::Git) }.map { |s| s.uri.to_s.sub(/\.git\z/, "") } }
new_git = git_remotes.(lock) - git_remotes.(base_lock)
fails << "new git sources: #{new_git.join(', ')}" unless new_git.empty?
fails << "mbleigh/acts-as-taggable-on git source still in the lockfile" if git_remotes.(lock).any? { |u| u.include?("mbleigh/acts-as-taggable-on") }

allowed = %w[
  rails railties actioncable actionmailbox actionmailer actionpack actiontext actionview activejob
  activemodel activerecord activestorage activesupport action_text-trix
  acts-as-taggable-on uri tsort mini_magick image_processing ruby-vips jbuilder goldiloader
  deep_cloneable loofah nokogiri rails-html-sanitizer roadie
]
changed = (specs.keys | base_specs.keys).reject { |n| ver(specs, n) == ver(base_specs, n) }
outside = changed - allowed
fails << "gems changed outside the allowed set: #{outside.sort.join(', ')}" unless outside.empty?

puts "rails #{rails} | changed: #{changed.sort.join(' ')}"
if fails.empty?
  puts "M6 DEPS PROBE PASS"
else
  puts fails
  exit 1
end
