# frozen_string_literal: true

# Golden generator of fork-updates-r10l (coordinator's probe, never part of the suite). Runs every
# case of $R10L_CASES (r10l_cases.json) through the WhatsApp adapters (Twilio, Vonage, MessageBird,
# Dialog360: send_message, Dialog360#send_template_message) with HTTP stubbed by WebMock (every request
# recorded: method, URI, the headers that matter, raw body) and writes the cases with their "outcome"
# (returned value, requests, rows of the conversation tables afterwards) to $R10L_GOLDEN_OUT as
# JSON.pretty_generate + "\n". r10l_tests.rb runs it against BASE's code: the committed fixture must be
# exactly that output. The helpers below are the helpers of the executor's spec, character for character.

require "rails_helper"
require "webmock"

RSpec.describe MessageApis::BasePackage, "r10l golden generator" do
  include WebMock::API

  cases = JSON.parse(File.read(ENV.fetch("R10L_CASES")))
  results = {}

  around do |example|
    WebMock.enable!
    example.run
  ensure
    WebMock.reset!
    WebMock.disable!
  end

  def api_class(provider)
    { "twilio" => MessageApis::Twilio::Api, "vonage" => MessageApis::Vonage::Api,
      "message_bird" => MessageApis::MessageBird::Api, "dialog360" => MessageApis::Dialog360::Api }.fetch(provider)
  end

  def canon(obj)
    case obj
    when Faraday::Response then { "@response" => { "status" => obj.status, "body" => obj.body } }
    when ActiveRecord::Base then { "@record" => obj.class.name, "id" => obj.id }
    when Hash then obj.to_h { |k, v| [k.is_a?(Symbol) ? ":#{k}" : k.to_str, canon(v)] }
    when Array then obj.map { |v| canon(v) }
    when Symbol then ":#{obj}"
    # Tokenable keys (SecureRandom.base58(24)) of records the call creates.
    when String then obj.match?(/\A[1-9A-HJ-NP-Za-km-z]{24}\z/) ? "@random-key" : obj
    when Integer, Float, true, false, nil then obj
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

  def build_user(app, spec)
    user = app.add_user(email: spec.fetch("email"))
    user.update_columns(properties: user.properties.merge("phone" => spec["phone"])) if spec.key?("phone")
    spec.fetch("profiles", []).each { |profile| user.external_profiles.create!(profile) }
    user
  end

  def build_conversation(app, spec, users)
    conversation = app.conversations.create!(main_participant: users.fetch(spec.fetch("user", 0)))
    conversation.update_columns(key: spec.fetch("key"))
    spec.fetch("channels", []).each { |channel| conversation.conversation_channels.create!(channel) }
    conversation
  end

  def build_part(conversation, spec, agent, provider)
    content = ConversationPartContent.new(spec.slice("serialized_content", "html_content"))
    part = conversation.messages.new(authorable: agent, messageable: content, private_note: spec["private_note"])
    return part unless spec.fetch("persist", true)

    part.save!
    spec.fetch("sent", []).each do |index|
      part.conversation_part_channel_sources.create!(provider: provider, message_source_id: "sent-#{index}", delivery_index: index)
    end
    part
  end

  def build_world(spec)
    app = FactoryBot.create(:app)
    app.update_columns(key: "app-key")
    agent = app.add_agent({ email: "agent@example.com", name: "Agent Smith" }).agent
    users = spec.fetch("users").map { |user| build_user(app, user) }
    conversations = spec.fetch("conversations", []).map { |conv| build_conversation(app, conv, users) }
    provider = api_class(spec.fetch("provider"))::PROVIDER
    part = build_part(conversations.first, spec["part"], agent, provider) if spec["part"]
    { app: app, users: users, conversations: conversations, part: part }
  end

  def call(api, spec, world)
    return api.send_message(world[:conversations].first, world[:part]) if spec.fetch("call") == "send_message"

    args = spec.fetch("args")
    selected = args.key?("selected_index") ? world[:users].fetch(args["selected_index"]).id : args["selected_user"]
    api.send_template_message(template: args["template"], conversation_key: args["conversation_key"],
                              parameters: args["parameters"], selected_user: selected)
  end

  def stub_http(spec, requests)
    stub_request(:any, /.*/).to_return do |request|
      requests << { "method" => request.method.to_s.upcase, "uri" => request.uri.omit(:port).to_s,
                    "headers" => request.headers.slice("Authorization", "Content-Type", "Accept", "X-Token", "D360-Api-Key"),
                    "body" => request.body }
      reply = spec.fetch("replies", [])[requests.size - 1] || spec.fetch("reply", {})
      { status: reply.fetch("status", 200), body: reply.fetch("body", "{}") }
    end
  end

  def build_api(spec, world)
    allow(Chaskiq::Config).to receive(:get).and_call_original
    allow(Chaskiq::Config).to receive(:get).with("HOST").and_return("https://chat.example.com")
    config = spec.fetch("config")
    config = config.merge(package: double("package", app: world[:app])) if spec.fetch("provider") == "dialog360"
    api_class(spec.fetch("provider")).new(config: config)
  end

  def table_rows(model, only = nil)
    skip = model.columns.select { |column| column.type == :datetime }.map(&:name)
    model.order(:id).map do |record|
      attrs = record.attributes.except(*skip).compact
      canon(only ? attrs.slice(*only) : attrs)
    end
  end

  def db_snapshot
    { "conversations" => table_rows(Conversation), "parts" => table_rows(ConversationPart),
      "contents" => table_rows(ConversationPartContent), "events" => table_rows(ConversationPartEvent),
      "channel_sources" => table_rows(ConversationPartChannelSource), "channels" => table_rows(ConversationChannel),
      "external_profiles" => table_rows(ExternalProfile), "app_users" => table_rows(AppUser, %w[id type email properties]) }
  end

  def run_case(spec)
    world = build_world(spec)
    requests = []
    stub_http(spec, requests)
    api = build_api(spec, world)
    result = outcome { call(api, spec, world) }
    { "result" => result, "requests" => requests, "db" => db_snapshot }
  end

  cases.each do |c|
    it c["name"] do
      results[c["name"]] = run_case(c)
    end
  end

  after(:all) do
    golden = cases.map { |c| c.merge("outcome" => results.fetch(c["name"])) }
    File.write(ENV.fetch("R10L_GOLDEN_OUT"), "#{JSON.pretty_generate(golden)}\n")
  end
end
