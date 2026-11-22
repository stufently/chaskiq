# frozen_string_literal: true

require "rails_helper"
require "webmock"

RSpec.describe MessageApis::Slack::Api, "Block Kit payloads" do
  include WebMock::API

  golden = JSON.parse(Rails.root.join("spec/fixtures/slack/block_kit_payloads.json").read)

  around do |example|
    WebMock.enable!
    I18n.with_locale(:en) { Time.use_zone("UTC") { example.run } }
  ensure
    WebMock.reset!
    WebMock.disable!
  end

  def canon(obj)
    case obj
    when ActiveRecord::Base
      { "@record" => obj.class.name, "attributes" => canon(obj.attributes.except("created_at", "updated_at")) }
    when Hash then obj.to_h { |k, v| [k.is_a?(Symbol) ? ":#{k}" : k.to_str, canon(v)] }
    when Array then obj.map { |v| canon(v) }
    when Symbol then ":#{obj}"
    when String, Integer, Float, true, false, nil then obj
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

  def build_participant(app, spec)
    user = spec["type"] == "Lead" ? app.add_lead(email: spec["email"]) : app.add_user(email: spec["email"])
    user.update_columns(spec.fetch("columns", {}).merge("properties" => user.properties.merge(spec.fetch("properties", {}))))
    user.reload
  end

  def build_part(conversation, spec, people)
    messageable = case spec.fetch("kind")
                  when "content" then ConversationPartContent.new(spec.slice("serialized_content", "html_content"))
                  when "block" then ConversationPartBlock.new(blocks: {}, data: spec["data"], state: spec["state"])
                  when "event" then ConversationPartEvent.new(action: spec["action"], data: spec["data"])
                  end
    part = conversation.messages.create!(authorable: people.fetch(spec.fetch("author")), messageable: messageable)
    part.conversation_part_channel_sources.create!(provider: "slack", message_source_id: spec["delivered"]) if spec["delivered"]
    part
  end

  def build_world(spec)
    return {} unless spec["conversation"]

    app = FactoryBot.create(:app)
    app.update_columns(key: "app-key")
    people = spec.fetch("agents", {}).to_h { |name, attrs| [name, app.add_agent(attrs.symbolize_keys).agent] }
    people["participant"] = build_participant(app, spec.fetch("participant"))
    conversation = build_conversation(app, spec["conversation"], people)
    parts = spec.fetch("messages", []).map { |m| build_part(conversation, m, people) }
    { conversation: conversation.reload, parts: parts }
  end

  def build_conversation(app, conv, people)
    conversation = app.conversations.create!(main_participant: people["participant"], assignee: people[conv["assignee"]])
    conversation.update_columns(key: "conversation-key", state: conv.fetch("state", "opened"),
                                priority: conv.fetch("priority", false), created_at: Time.zone.parse("2026-01-02T03:04:05Z"))
    Array(conv["slack_ts"]).each { |ts| conversation.conversation_channels.create!(provider: "slack", provider_channel_id: ts) }
    conversation
  end

  def call(api, spec, world)
    conversation = world[:conversation]
    case spec.fetch("call")
    when "thread_head" then api.thread_head(conversation)
    when "notify_added" then api.notify_added(conversation)
    when "update_thread_head" then api.update_thread_head(conversation, spec["slack_id"])
    when "notify_message"
      api.notify_message(conversation: conversation, part: world[:parts].fetch(spec.fetch("part")), channel: nil)
    when "serialize_content" then api.serialize_content(spec.fetch("event"))
    end
  end

  def stub_http(spec, requests)
    stub_request(:any, /.*/).to_return do |request|
      verb = request.method.to_s.upcase
      uri = request.uri.omit(:port)
      requests << { "method" => verb, "uri" => uri.to_s, "authorization" => request.headers["Authorization"],
                    "content_type" => request.headers["Content-Type"], "body" => request.body }
      reply = spec.fetch("replies", {}).fetch("#{verb} #{uri.omit(:query)}", {})
      { status: reply.fetch("status", 200), body: reply.fetch("body", "{}") }
    end
  end

  def build_api(spec, uploads)
    allow(Chaskiq::Config).to receive(:get).and_call_original
    allow(Chaskiq::Config).to receive(:get).with("HOST").and_return("https://chat.example.com")
    api = described_class.new(config: spec.fetch("config"))
    allow(api).to receive(:direct_upload) do |file:, filename:, content_type:|
      uploads << { "filename" => filename, "content_type" => content_type, "data" => file.read }
      spec.fetch("uploads", {})[filename]&.symbolize_keys
    end
    api
  end

  def run_case(spec)
    world = build_world(spec)
    requests = []
    uploads = []
    stub_http(spec, requests)
    api = build_api(spec, uploads)
    result = outcome { call(api, spec, world) }
    { "result" => result, "requests" => requests, "uploads" => uploads }
  end

  golden.each do |c|
    it c["name"] do
      expect(JSON.pretty_generate(run_case(c))).to eq(JSON.pretty_generate(c["outcome"]))
    end
  end
end
