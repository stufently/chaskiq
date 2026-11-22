# frozen_string_literal: true

require "rails_helper"
require "webmock"

RSpec.describe MessageApis::OpenAi::Api do
  include WebMock::API

  let(:app) { FactoryBot.create(:app) }
  let(:user) { app.add_user(email: "r10n-user@test.cl", first_name: "User") }
  let(:bot) { app.agents.bots.first }
  let(:conversation) { app.conversations.create!(main_participant: user) }
  let(:api) { described_class.new(config: { "api_secret" => "r10n-test-token" }) }
  let(:endpoint) { "https://api.openai.com/v1/chat/completions" }
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }
  let(:cache_key) { "/conversation/#{conversation.key}/openai" }

  around do |example|
    WebMock.enable!
    example.run
  ensure
    WebMock.reset!
    WebMock.disable!
  end

  before do
    allow(ApiChannelNotificatorJob).to receive(:perform_later)
    allow(Rails).to receive(:cache).and_return(cache)
    conversation.conversation_channels.create!(
      provider: "open_ai",
      provider_channel_id: conversation.id,
      data: { prompt: "r10n prompt" }
    )
  end

  def create_part(text, author: user, input_blocks: [text])
    document = {
      type: "doc",
      content: [{ type: "paragraph", content: [{ type: "text", text: text }] }],
      blocks: input_blocks.map { |block| { text: block } }
    }
    conversation.add_message(
      from: author,
      message: { html_content: text, serialized_content: document.to_json }
    )
  end

  def notify(part)
    api.notify_message(conversation: conversation, part: part, channel: nil)
  end

  it "skips parts when the OpenAI channel is absent" do
    conversation.conversation_channels.destroy_all

    expect(notify(create_part("hello"))).to be_nil
    assert_not_requested(:post, endpoint)
  end

  it "skips non-content parts" do
    part = conversation.add_message_event(action: "assigned", data: {})

    expect(notify(part)).to be_nil
    assert_not_requested(:post, endpoint)
  end

  it "removes the OpenAI channel when a human agent replies" do
    agent = app.add_agent({ email: "r10n-human@test.cl" }).agent

    expect(notify(create_part("human reply", author: agent))).to eq(true)
    expect(conversation.conversation_channels.where(provider: "open_ai")).to be_empty
    assert_not_requested(:post, endpoint)
  end

  it "skips an already delivered part" do
    part = create_part("sent")
    part.conversation_part_channel_sources.create!(provider: "open_ai", message_source_id: "already-sent")

    expect(notify(part)).to be_nil
    assert_not_requested(:post, endpoint)
  end

  it "keeps the channel and skips replies from a bot" do
    expect(notify(create_part("automatic reply", author: bot))).to be_nil
    expect(conversation.conversation_channels.where(provider: "open_ai")).to exist
    assert_not_requested(:post, endpoint)
  end

  def stub_chat_response(body)
    stub_request(:post, endpoint)
      .with(headers: { "Authorization" => "Bearer r10n-test-token", "Content-Type" => "application/json; charset=utf-8" })
      .to_return do |request|
        yield request if block_given?
        { status: 200, body: body.to_json }
      end
  end

  it "sends ordered history and caches the current prompt before HTTP" do
    create_part("first question")
    create_part("first answer", author: bot)
    part = create_part("current", input_blocks: %w[hello world])
    history = [
      { "role" => "user", "content" => "first question" },
      { "role" => "assistant", "content" => "first answer" }
    ]
    input = { role: "user", content: "hello world" }
    request_stub = stub_chat_response({ "choices" => [] }) do |request|
      expect(cache.read(cache_key)).to eq(history + [input])
      expected = {
        "model" => "gpt-3.5-turbo",
        "messages" => [{ "role" => "system", "content" => "r10n prompt" }, *history, input.stringify_keys],
        "user" => user.id.to_s
      }
      expect(JSON.parse(request.body)).to eq(expected)
    end

    expect(notify(part)).to be_nil
    assert_requested(request_stub, times: 1)
  end

  it "uses an existing cached history without rebuilding it" do
    create_part("database history")
    part = create_part("new question")
    cached = { "role" => "assistant", "content" => "cached answer" }
    cache.write(cache_key, [cached])
    request_stub = stub_chat_response({ "choices" => [] }) do |request|
      expect(JSON.parse(request.body)["messages"].drop(1))
        .to eq([cached, { "role" => "user", "content" => "new question" }])
    end

    notify(part)
    assert_requested(request_stub, times: 1)
  end

  it "persists the reply as bot content and leaves the string-keyed ID unused" do
    app.add_bot_agent({ email: "r10n-second-bot@test.cl" })
    part = create_part("question")
    stub_chat_response({ "id" => "response-id", "choices" => [{ "message" => { "content" => "GPT reply" } }] })

    expect { notify(part) }.to change { conversation.messages.count }.by(1)

    reply = conversation.messages.order(:id).last
    expect(reply.authorable).to eq(bot)
    expect(reply.message.html_content).to eq("GPT reply")
    expect(reply.message.parsed_content).to eq("blocks" => [{ "type" => "text", "text" => "GPT reply" }])
    expect(reply.conversation_part_channel_sources.where(provider: "open_ai")).to be_empty
  end

  it "leaves the conversation unchanged when the response has no content" do
    part = create_part("question")
    stub_chat_response({ "choices" => [{ "message" => {} }] })

    expect { notify(part) }.not_to change(conversation.messages, :count)
  end
end
