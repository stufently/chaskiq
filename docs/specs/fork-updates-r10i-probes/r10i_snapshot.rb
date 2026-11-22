# frozen_string_literal: true

# Snapshot probe for fork-updates-r10i (run by r10i_snapshot_gate.sh inside the CI image with the app's gems:
# `bundle exec ruby`, ActiveSupport only, no Rails app, no database, no network).
# Usage: ruby r10i_snapshot.rb <r10i_config.json> <presenter.rb> <out_dir>
# Loads the given MessageApis::Dialog360::Presenter file (BASE copy or the tree's) under Coverage and, for every
# entry of "snapshots" (name, kind, ctx_keys, ctx, api), calls Presenter.configure_hook(kind:, ctx:) with
# ctx[:package] = a fake package whose message_api_klass is a fake API answering only what "api" lists:
#   templates_json - body returned by retrieve_templates(offset:);
#   send_json      - JSON text whose value send_template_message(...) returns;
#   users          - [{id, type, display_name, email, phone, label}] returned by
#                    package.app.app_users.limit(n).ransack(q).result; label is what
#                    get_profile_for_participant_label(user) returns.
# package.app.key is "app-key-1". Every call to the fakes is recorded in order as {call, args}.
# ctx_keys "indifferent": the ctx as a HashWithIndifferentAccess (as the GraphQL call_hook passes it);
# "symbol": a plain Hash with symbol keys at every level.
# Writes <out_dir>/<name>.json = JSON.pretty_generate({case, kind, ctx_keys, ctx, api, calls, outcome}) + "\n",
# outcome = {result: <returned value>} or {raised: {class, message}} (StandardError raised by configure_hook).
# Checks (each failure is a spec defect when run on BASE):
#   - every result round-trips through JSON (only symbol keys, JSON values): a snapshot pins the whole value,
#     key order included;
#   - a call to the fake API that the case does not stub fails the probe;
#   - COVERAGE (BASE only, flag --coverage): every branch of the presenter file is taken by some case.
# Prints "R10I SNAPSHOTS <n> cases[, <b> branches covered]" or "FAIL: ..." lines; exit 1 on any failure.
require "coverage"
require "json"
require "fileutils"
require "logger"
require "base64"
require "active_support/all"

cfg_path, presenter, out_dir, flag = ARGV
abort "usage: r10i_snapshot.rb <config> <presenter.rb> <out_dir> [--coverage]" unless out_dir

module Rails
  def self.logger
    @logger ||= Logger.new(nil)
  end
end

module MessageApis; end
Coverage.start(branches: true)
load File.expand_path(presenter)
P = MessageApis::Dialog360::Presenter
FAILS = []
cases = JSON.parse(File.read(cfg_path)).fetch("snapshots")
FAILS << "config lists no snapshots" if cases.empty?
names = cases.map { |c| c.fetch("name") }
FAILS << "duplicate snapshot names" if names.uniq.size != names.size

class Unstubbed < StandardError; end

class Recorder
  attr_reader :calls

  def initialize(api)
    @api = api
    @calls = []
  end

  def record(call, *args)
    @calls << { "call" => call, "args" => JSON.parse(JSON.generate(args)) }
  end

  def stub(key)
    raise Unstubbed, "unstubbed #{key}" unless @api.key?(key)

    @api[key]
  end
end

class FakeApi
  def initialize(rec)
    @rec = rec
  end

  def retrieve_templates(**kw)
    @rec.record("retrieve_templates", kw)
    @rec.stub("templates_json")
  end

  def send_template_message(**kw)
    @rec.record("send_template_message", kw)
    JSON.parse(@rec.stub("send_json"))
  end

  def get_profile_for_participant_label(user)
    @rec.record("get_profile_for_participant_label", user.id)
    user.label
  end
end

FakeUser = Struct.new(:id, :type, :display_name, :email, :phone, :label, keyword_init: true)

class FakeAppUsers
  def initialize(rec)
    @rec = rec
  end

  def limit(num)
    @rec.record("limit", num)
    self
  end

  def ransack(query)
    @rec.record("ransack", query)
    self
  end

  def result
    @rec.record("result")
    @rec.stub("users").map { |u| FakeUser.new(**u.transform_keys(&:to_sym)) }
  end
end

FakeApp = Struct.new(:key, :app_users)
FakePackage = Struct.new(:message_api_klass, :app)

FileUtils.mkdir_p(out_dir)
cases.each do |c|
  name = c.fetch("name")
  FAILS << "#{name}: name must match [a-z0-9_]+" unless name.match?(/\A[a-z0-9_]+\z/)
  rec = Recorder.new(c.fetch("api"))
  package = FakePackage.new(FakeApi.new(rec), FakeApp.new("app-key-1", FakeAppUsers.new(rec)))
  ctx = case c.fetch("ctx_keys")
        when "indifferent" then c.fetch("ctx").with_indifferent_access.merge(package: package)
        when "symbol" then JSON.parse(JSON.generate(c.fetch("ctx")), symbolize_names: true).merge(package: package)
        else FAILS << "#{name}: ctx_keys must be indifferent or symbol"
             next
        end
  begin
    outcome = { result: P.configure_hook(kind: c.fetch("kind"), ctx: ctx) }
  rescue Unstubbed => e
    FAILS << "#{name}: the case calls the fake API without a stub (#{e.message})"
    next
  rescue StandardError => e
    outcome = { raised: { class: e.class.name, message: e.message } }
  end
  if JSON.parse(JSON.generate(outcome), symbolize_names: true) != outcome
    FAILS << "#{name}: result does not round-trip through JSON (non-symbol key or non-JSON value)"
  end
  doc = { "case" => name, "kind" => c["kind"], "ctx_keys" => c["ctx_keys"], "ctx" => c["ctx"], "api" => c["api"],
          "calls" => rec.calls, "outcome" => outcome }
  File.write(File.join(out_dir, "#{name}.json"), "#{JSON.pretty_generate(doc)}\n")
end
branches = Coverage.result.fetch(File.expand_path(presenter)).fetch(:branches)
taken = 0
branches.each do |(kind, _id, line, *), targets|
  targets.each do |(target, _tid, tline, *), count|
    if count.zero?
      FAILS << "COVERAGE: no case takes the #{target} branch of the #{kind} at line #{line} (#{tline})" if flag == "--coverage"
    else
      taken += 1
    end
  end
end
FAILS.each { |f| puts "FAIL: #{f}" }
exit 1 unless FAILS.empty?
puts "R10I SNAPSHOTS #{cases.size} cases#{", #{taken} branches covered" if flag == '--coverage'}"
