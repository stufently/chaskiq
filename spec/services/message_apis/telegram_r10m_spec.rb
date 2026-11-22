# frozen_string_literal: true

require "rails_helper"

RSpec.describe MessageApis::Telegram::Api do
  include WebMock::API

  let(:app) { FactoryBot.create(:app) }
  let!(:agent_role) { app.add_agent({ email: "agent-tg@test.cl" }) }
  let(:app_package) { AppPackage.find_by(name: "Telegram") }

  let(:pkg) do
    AppPackagesCatalog.update_all
    allow_any_instance_of(AppPackageIntegration).to receive(:handle_registration).and_return({})
    app.app_package_integrations.create(
      api_secret: "secret",
      api_key: "key",
      user_id: "111",
      access_token: "TOKEN",
      app_package: app_package
    )
  end

  let(:api) { pkg.message_api_klass }

  around do |example|
    WebMock.enable!
    example.run
  ensure
    WebMock.reset!
    WebMock.disable!
  end

  def build_conversation_with_channel(channel_id: "12345")
    participant = app.add_anonymous_user(properties: { name: "Test User" })
    participant.external_profiles.create(provider: "telegram", profile_id: "999")
    app.conversations.create(
      main_participant: participant,
      conversation_channels_attributes: [
        { provider: "telegram", provider_channel_id: channel_id }
      ]
    )
  end

  def build_part_with_content(conversation, html_content: nil, serialized_content: nil)
    msg_opts = {}
    msg_opts[:html_content] = html_content if html_content
    msg_opts[:serialized_content] = serialized_content if serialized_content
    conversation.add_message(
      from: conversation.main_participant,
      message: msg_opts
    )
  end

  describe "send_message" do
    let(:conversation) { build_conversation_with_channel }
    let(:base_url) { "https://api.telegram.org/botTOKEN" }

    it "returns nil for a private note without making any request" do
      part = build_part_with_content(conversation, html_content: "secret")
      allow(part).to receive(:private_note?).and_return(true)

      result = api.send_message(conversation, part)
      expect(result).to be_nil
      assert_not_requested(:post, /api\.telegram\.org/)
    end

    it "returns nil when both serialized_content and html_content are blank" do
      part = build_part_with_content(conversation, html_content: "")
      result = api.send_message(conversation, part)
      expect(result).to be_nil
      assert_not_requested(:post, /api\.telegram\.org/)
    end

    it "falls back to HTML text when serialized_content is blank" do
      part = build_part_with_content(conversation, html_content: "<p>hello <b>world</b></p>")
      stub_request(:post, "#{base_url}/sendMessage")
        .to_return(status: 200, body: '{"ok":true,"result":{"message_id":1}}')

      api.send_message(conversation, part)

      assert_requested(:post, "#{base_url}/sendMessage") do |req|
        body = JSON.parse(req.body)
        body["chat_id"] == "12345" && body["text"] == "hello world"
      end
    end

    it "returns nil when serialized_content produces empty blocks" do
      sc = { type: "doc", content: [] }.to_json
      part = build_part_with_content(conversation, serialized_content: sc)
      result = api.send_message(conversation, part)
      expect(result).to be_nil
      assert_not_requested(:post, /api\.telegram\.org/)
    end

    it "returns nil when serialized_content is corrupted JSON" do
      part = conversation.send(:process_message_part,
                               from: conversation.main_participant,
                               message: { html_content: "test", serialized_content: '{"type":"doc","content":[]}' })
      part.save!
      part.messageable.update_column(:serialized_content, "{not valid json!!")

      result = api.send_message(conversation, part)
      expect(result).to be_nil
      assert_not_requested(:post, /api\.telegram\.org/)
    end

    it "returns nil when conversation has no telegram channel" do
      participant = app.add_anonymous_user(properties: { name: "No Channel" })
      no_channel_conv = app.conversations.create(main_participant: participant)
      part = build_part_with_content(no_channel_conv, html_content: "hello")

      result = api.send_message(no_channel_conv, part)
      expect(result).to be_nil
      assert_not_requested(:post, /api\.telegram\.org/)
    end

    it "sends text to the exact Telegram URI with correct JSON and headers" do
      sc = { type: "doc", content: [{ type: "paragraph", content: [{ type: "text", text: "hi there" }] }] }.to_json
      part = build_part_with_content(conversation, serialized_content: sc)
      stub_request(:post, "#{base_url}/sendMessage")
        .to_return(status: 200, body: '{"ok":true,"result":{"message_id":42}}')

      api.send_message(conversation, part)

      assert_requested(:post, "#{base_url}/sendMessage") do |req|
        body = JSON.parse(req.body)
        body["chat_id"] == "12345" &&
          body["text"] == "hi there" &&
          req.headers["Content-Type"] == "application/json" &&
          req.headers["Accept"] == "application/json"
      end
    end

    it "sends an image block via sendPhoto with caption on the first attachment" do
      sc = {
        type: "doc",
        content: [
          { type: "paragraph", content: [{ type: "text", text: "look at this" }] },
          { type: "ImageBlock", attrs: { url: "https://cdn.example.com/photo.jpg", caption: "look at this" } }
        ]
      }.to_json

      part = build_part_with_content(conversation, serialized_content: sc)

      allow(MessageApis::BlockManager).to receive(:absolute_url)
        .and_call_original
      allow(MessageApis::BlockManager).to receive(:absolute_url)
        .with("https://cdn.example.com/photo.jpg")
        .and_return("https://cdn.example.com/photo.jpg")

      stub_request(:post, "#{base_url}/sendPhoto")
        .to_return(status: 200, body: '{"ok":true,"result":{"message_id":5}}')

      api.send_message(conversation, part)

      assert_requested(:post, "#{base_url}/sendPhoto") do |req|
        body = JSON.parse(req.body)
        body["chat_id"] == "12345" &&
          body["photo"] == "https://cdn.example.com/photo.jpg" &&
          body["caption"] == "look at this"
      end
    end

    it "sends text fallback after all attachments fail" do
      sc = {
        type: "doc",
        content: [
          { type: "paragraph", content: [{ type: "text", text: "fallback text" }] },
          { type: "ImageBlock", attrs: { url: "https://cdn.example.com/bad.jpg", caption: "fallback text" } }
        ]
      }.to_json

      part = build_part_with_content(conversation, serialized_content: sc)

      allow(MessageApis::BlockManager).to receive(:absolute_url)
        .and_call_original
      allow(MessageApis::BlockManager).to receive(:absolute_url)
        .with("https://cdn.example.com/bad.jpg")
        .and_return("https://cdn.example.com/bad.jpg")

      stub_request(:post, "#{base_url}/sendPhoto")
        .to_return(status: 500, body: '{"ok":false}')
      stub_request(:post, "#{base_url}/sendMessage")
        .to_return(status: 200, body: '{"ok":true,"result":{"message_id":7}}')

      api.send_message(conversation, part)

      assert_requested(:post, "#{base_url}/sendMessage") do |req|
        body = JSON.parse(req.body)
        body["text"] == "fallback text"
      end
    end

    it "sends two attachments in order with caption only on the first successful" do
      sc = {
        type: "doc",
        content: [
          { type: "paragraph", content: [{ type: "text", text: "two photos" }] },
          { type: "ImageBlock", attrs: { url: "https://cdn.example.com/first.jpg", caption: "two photos" } },
          { type: "ImageBlock", attrs: { url: "https://cdn.example.com/second.jpg", caption: "two photos" } }
        ]
      }.to_json

      part = build_part_with_content(conversation, serialized_content: sc)

      allow(MessageApis::BlockManager).to receive(:absolute_url)
        .and_call_original
      allow(MessageApis::BlockManager).to receive(:absolute_url)
        .with("https://cdn.example.com/first.jpg")
        .and_return("https://cdn.example.com/first.jpg")
      allow(MessageApis::BlockManager).to receive(:absolute_url)
        .with("https://cdn.example.com/second.jpg")
        .and_return("https://cdn.example.com/second.jpg")

      requests = []
      stub_request(:post, "#{base_url}/sendPhoto").to_return do |request|
        requests << JSON.parse(request.body)
        { status: 200, body: { ok: true, result: { message_id: requests.length } }.to_json }
      end

      api.send_message(conversation, part)

      expect(requests).to eq([
        { "chat_id" => "12345", "photo" => "https://cdn.example.com/first.jpg", "caption" => "two photos" },
        { "chat_id" => "12345", "photo" => "https://cdn.example.com/second.jpg" }
      ])
    end
  end
end
