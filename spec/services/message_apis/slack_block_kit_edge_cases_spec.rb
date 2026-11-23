# frozen_string_literal: true

require "rails_helper"
require "webmock"

RSpec.describe MessageApis::Slack::Api, "Block Kit edge cases" do
  include WebMock::API

  around do |example|
    WebMock.enable!
    I18n.with_locale(:en) { Time.use_zone("UTC") { example.run } }
  ensure
    WebMock.reset!
    WebMock.disable!
  end

  let(:config) do
    {
      "access_token" => "xoxb-bot",
      "access_token_secret" => "xoxp-user",
      "slack_channel_id" => "C-USERS",
      "slack_channel_id_leads" => "C-LEADS"
    }
  end

  def build_api
    allow(Chaskiq::Config).to receive(:get).and_call_original
    allow(Chaskiq::Config).to receive(:get).with("HOST").and_return("https://chat.example.com")
    described_class.new(config: config)
  end

  def build_conversation_with_slack_channel(app:, participant:)
    conversation = app.conversations.create!(main_participant: participant)
    conversation.conversation_channels.create!(provider: "slack", provider_channel_id: "171.1")
    conversation
  end

  # AC-002: serialize_content with a Slack file where direct_upload raises StandardError.
  # Production code catches the exception inside fetch_attachment (rescue StandardError)
  # and returns nil, so serialize_content returns nil — the exception does not escape.
  # Mutation M2 moves handle_direct_upload out of the rescue, so the exception propagates.
  describe "serialize_content when direct_upload raises" do
    let(:api) { build_api }
    let(:event) do
      {
        "type" => "message",
        "text" => "see attached",
        "ts" => "9.9",
        "files" => [
          {
            "id" => "F1",
            "mode" => "hosted",
            "title" => "doc.pdf",
            "mimetype" => "application/pdf",
            "url_private_download" => "https://files.slack.com/files-pri/T1-F1/doc.pdf"
          }
        ]
      }
    end

    before do
      stub_request(:get, "https://files.slack.com/files-pri/T1-F1/doc.pdf")
        .to_return(body: "PDF-BYTES")
      allow(api).to receive(:direct_upload).and_raise(StandardError, "upload boom")
    end

    it "returns nil without raising and calls direct_upload exactly once" do
      expect(api.serialize_content(event)).to be_nil
      expect(api).to have_received(:direct_upload).once
    end
  end

  # AC-003: notify_message for a replied ConversationPartBlock whose authorable is nil.
  # Production code calls format_user_name(part.authorable) before checking the messageable
  # type; format_user_name(nil) calls nil.display_name and raises NoMethodError.
  # Mutation M3 guards the format_user_name call for ConversationPartBlock, so the
  # exception disappears and a chat.postMessage is sent instead.
  describe "notify_message for a replied block without an author" do
    let(:api) { build_api }
    let(:app) { FactoryBot.create(:app) }
    let!(:participant) { app.add_lead(email: "ana@example.com") }
    let!(:conversation) { build_conversation_with_slack_channel(app: app, participant: participant) }
    let!(:part) do
      block = ConversationPartBlock.new(blocks: {}, data: { "label" => "Yes" }, state: "replied")
      conversation.messages.create!(authorable: nil, messageable: block)
    end

    before do
      stub_request(:post, "https://slack.com/api/chat.postMessage")
        .to_return(body: '{"ok":true,"ts":"1700000000.000100"}')
    end

    it "raises NoMethodError from display_name on the missing author" do
      expect do
        api.notify_message(conversation: conversation, part: part, channel: nil)
      end.to raise_error(NoMethodError, /display_name/)
    end

    it "does not post any chat message" do
      begin
        api.notify_message(conversation: conversation, part: part, channel: nil)
      rescue NoMethodError
        nil
      end
      assert_not_requested(:post, "https://slack.com/api/chat.postMessage")
    end
  end

  # AC-004: assigned event where users.lookupByEmail returns a user without an id.
  # Production code builds "\n <@#{slack_user['id']}>" whenever slack_user is present;
  # a user hash without "id" produces the dangling mention "\n <@>".
  # Mutation M4 requires slack_user&.dig("id").present?, suppressing the mention entirely.
  describe "notify_message assignment when lookupByEmail returns a user without id" do
    let(:api) { build_api }
    let(:app) { FactoryBot.create(:app) }
    let!(:agent_bob) { app.add_agent({ email: "bob@example.com", name: "Bob Agent" }).agent }
    let!(:participant) { app.add_lead(email: "ana@example.com") }
    let!(:conversation) { build_conversation_with_slack_channel(app: app, participant: participant) }
    let!(:part) do
      event = ConversationPartEvent.new(action: "assigned", data: { "email" => "ghost@example.com", "name" => "Ghost" })
      conversation.messages.create!(authorable: agent_bob, messageable: event)
    end

    let(:expected_event_block) do
      {
        "type" => "section",
        "text" => {
          "type" => "mrkdwn",
          "text" => "*event*: assigned \n *EMAIL*: ghost@example.com *NAME*: Ghost\n <@>"
        }
      }
    end

    before do
      stub_request(:get, %r{slack\.com/api/users\.lookupByEmail})
        .to_return(body: '{"ok":true,"user":{"name":"x"}}')
      stub_request(:post, "https://slack.com/api/chat.postMessage")
        .to_return(body: '{"ok":true,"ts":"1700000000.000100"}')
    end

    it "posts the event block with the dangling mention" do
      api.notify_message(conversation: conversation, part: part, channel: nil)

      assert_requested(:post, "https://slack.com/api/chat.postMessage") do |req|
        blocks = JSON.parse(req.body)["blocks"]
        blocks.any? { |b| b == expected_event_block }
      end
    end
  end
end
