# frozen_string_literal: true

require "rails_helper"
require "webmock"

RSpec.describe MessageApis::Slack::Api do
  include WebMock::API

  let(:app) { FactoryBot.create(:app) }
  let(:user) { app.add_user(email: "user@test.cl") }
  let(:api) { described_class.new(config: { "access_token" => "x", "channel_id" => "C1" }) }

  around do |example|
    WebMock.enable!
    example.run
  ensure
    WebMock.reset!
    WebMock.disable!
  end

  def setup_conversation
    conversation = app.start_conversation(message: { text_content: "hi" }, from: user)
    conversation.conversation_channels.create!(provider: "slack", provider_channel_id: "171.1")
    conversation
  end

  def notify_with_event(conversation, event_data)
    part = conversation.messages.create!(authorable: user, event: { action: "closed", data: event_data })
    api.notify_message(conversation: conversation, part: part, channel: nil)
    part
  end

  describe "#notify_message with ConversationPartEvent" do
    it "does not raise when data is nil and posts event block" do
      conversation = setup_conversation
      calls = []
      allow(api).to receive(:post_message) do |message, blocks, **_opts|
        calls << { message: message, blocks: blocks }
        instance_double(Faraday::Response, body: { ok: true }.to_json)
      end

      expect { notify_with_event(conversation, nil) }.not_to raise_error
      expect(calls).not_to be_empty
      text = calls.last[:blocks].first["text"]["text"]
      expect(text).to eq("*event*: closed \n ")
    end

    it "does not raise when data is an array" do
      conversation = setup_conversation
      allow(api).to receive(:post_message).and_return(
        instance_double(Faraday::Response, body: { ok: true }.to_json)
      )

      expect { notify_with_event(conversation, %w[a b]) }.not_to raise_error
      expect(api).to have_received(:post_message)
    end

    it "formats hash data with LABEL and STATUS" do
      conversation = setup_conversation
      calls = []
      allow(api).to receive(:post_message) do |message, blocks, **_opts|
        calls << { message: message, blocks: blocks }
        instance_double(Faraday::Response, body: { ok: true }.to_json)
      end

      notify_with_event(conversation, { "label" => "Done", "status" => "ok", "id" => "1" })
      text = calls.last[:blocks].first["text"]["text"]
      expect(text).to eq("*event*: closed \n *LABEL*: Done *STATUS*: ok")
    end
  end
end
