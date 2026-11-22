# frozen_string_literal: true

require "rails_helper"

RSpec.describe MessageApis::InboxSections::Presenter, "hooks" do
  golden = JSON.parse(Rails.root.join("spec/fixtures/presenters/inbox_sections_hooks.json").read)

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

  golden.each do |c|
    it c["name"] do
      allow(Conversation).to receive(:find_by).with(key: c["ctx"]["conversation_key"])
                                              .and_return(build_conversation(c["conversation"]))
      ctx = ActionController::Parameters.new(c["ctx"])
      result = outcome { described_class.public_send("#{c['hook']}_hook", kind: c["kind"], ctx: ctx) }
      expect(JSON.pretty_generate(result)).to eq(JSON.pretty_generate(c["outcome"]))
    end
  end
end
