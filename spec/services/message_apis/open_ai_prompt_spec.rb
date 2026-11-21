# frozen_string_literal: true

require "rails_helper"

RSpec.describe MessageApis::OpenAi::Api, type: :service do
  let(:app) { FactoryBot.create(:app) }
  let(:agent) { app.add_agent({ email: "agent@test.cl" }).agent }
  let(:user) { app.add_user(email: "user@test.cl", first_name: "User") }

  let(:app_package) do
    AppPackage.create!(name: "OpenAi", state: "enabled", published: true)
  end

  let(:integration) do
    app.app_package_integrations.create!(
      app_package: app_package,
      settings: { api_secret: "sk-test", main_prompt: "test prompt" }
    )
  end

  let(:conversation) do
    app.start_conversation(
      message: { html_content: "initial" },
      from: user
    )
  end

  before do
    conversation.conversation_channels.create!(
      provider: "open_ai",
      provider_channel_id: conversation.id,
      data: { prompt: "test prompt" }
    )
  end

  describe "#previous_messages and #notify_message" do
    it "builds prompt from messages in id order and extracts text from blocks" do
      # Create initial message with content
      initial_part = conversation.messages.first
      initial_part.messageable.update!(
        serialized_content: {
          type: "doc",
          content: [{ type: "paragraph", content: [{ type: "text", text: "initial" }] }]
        }.to_json
      )

      # Create additional messages with content
      part1 = conversation.add_message(from: user, message: { html_content: "first" })
      part1.messageable.update!(
        serialized_content: {
          type: "doc",
          content: [{ type: "paragraph", content: [{ type: "text", text: "first" }] }]
        }.to_json
      )

      part2 = conversation.add_message(from: user, message: { html_content: "second" })
      part2.messageable.update!(
        serialized_content: {
          type: "doc",
          content: [{ type: "paragraph", content: [{ type: "text", text: "second" }] }]
        }.to_json
      )

      # Create the new part with blocks (the format expected by notify_message)
      part3 = conversation.add_message(from: user, message: { html_content: "hello world" })
      part3.messageable.update!(
        serialized_content: { type: "doc", blocks: [{ text: "hello" }, { text: "world" }], content: [] }.to_json
      )

      # Clear cache to ensure previous_messages fetches fresh data
      Rails.cache.delete("/conversation/#{conversation.key}/openai")

      api = described_class.allocate

      # Stub get_gpt_response to capture the messages
      captured_messages = nil
      allow(api).to receive(:get_gpt_response) do |_prompt, messages, _user_key|
        captured_messages = messages
        { id: "test-id", choices: [{ message: { content: "response" } }] }
      end

      api.notify_message(conversation: conversation, part: part3, channel: nil)

      # Check that messages are in order and blocks are joined
      expect(captured_messages).to be_present
      expect(captured_messages.length).to eq(4)
      # Previous messages have string keys, the appended one has symbol keys
      user_messages = captured_messages.select { |m| m["role"] == "user" || m[:role] == "user" }
      contents = user_messages.map { |m| m["content"] || m[:content] }
      # All previous messages (including initial) + current part's blocks joined
      expect(contents).to eq(["initial", "first", "second", "hello world"])
    end
  end
end
