# frozen_string_literal: true

# Golden generator of fork-updates-r10h2 (coordinator's probe, never part of the suite). Runs every
# case of $R10H_CASES (r10h2_cases.json) through MessageApis::InboxSections::Presenter, with
# Conversation.find_by stubbed to the case's conversation built from doubles, and writes the cases
# with their "outcome" to $R10H_GOLDEN_OUT as JSON.pretty_generate + "\n". r10h2_tests.rb runs it
# against BASE's code: the committed fixture must be exactly that output.
# outcome = canonical form of the returned value (symbol keys/values as ":name", parameters as
# {"@parameters" => to_unsafe_h}) or {"@raise" => class name} when the hook raises.
require "rails_helper"

RSpec.describe "r10h2 golden generator" do
  around do |example|
    I18n.with_locale(:en) { Time.use_zone("UTC") { example.run } }
  end

  def canon(obj)
    case obj
    when ActionController::Parameters then { "@parameters" => canon(obj.to_unsafe_h) }
    when Hash then obj.to_h { |k, v| [k.is_a?(Symbol) ? ":#{k}" : k.to_str, canon(v)] }
    when Array then obj.map { |v| canon(v) }
    when Symbol then ":#{obj}"
    when String, Integer, true, false, nil then obj
    else raise ArgumentError, "canon: #{obj.class}"
    end
  end

  def outcome
    result = yield
  rescue StandardError => e
    { "@raise" => e.class.name }
  else
    canon(result)
  end

  def time(value)
    value && Time.zone.parse(value)
  end

  def build_conversation(conv)
    return if conv.nil?

    user = conv["user"]&.to_h { |k, v| [k.to_sym, k.end_with?("_at") ? time(v) : v] }
    events = double("events")
    allow(events).to receive(:order).with("events.id asc").and_return(
      conv["events"].map { |e| double("event", id: e["id"], action: e["action"], created_at: time(e["created_at"])) }
    )
    double("conversation", main_participant: user && double("user", user), events: events, tag_list: conv["tags"],
                           assignee: conv["assignee"] && double("assignee", conv["assignee"].transform_keys(&:to_sym)),
                           app: double("app", key: conv["app_key"]))
  end

  it "writes the golden fixture" do
    cases = JSON.parse(File.read(ENV.fetch("R10H_CASES")))
    golden = cases.map do |c|
      allow(Conversation).to receive(:find_by).with(key: c["ctx"]["conversation_key"])
                                              .and_return(build_conversation(c["conversation"]))
      ctx = ActionController::Parameters.new(c["ctx"])
      c.merge("outcome" => outcome { hook(c["hook"], c["kind"], ctx) })
    end
    File.write(ENV.fetch("R10H_GOLDEN_OUT"), "#{JSON.pretty_generate(golden)}\n")
    expect(golden.size).to eq(cases.size)
  end

  def hook(name, kind, ctx)
    MessageApis::InboxSections::Presenter.public_send("#{name}_hook", kind: kind, ctx: ctx)
  end
end
