# frozen_string_literal: true

require "rails_helper"

RSpec.describe MessageApis::Twitter::Api do
  include WebMock::API

  let(:app) { FactoryBot.create(:app) }
  let!(:agent) { app.add_agent({ email: "agent-tw@test.cl" }) }
  let(:app_package) { AppPackage.find_by(name: "Twitter") }

  let(:twitter_owner_id) { "7472512" }
  let(:twitter_user_id) { "1140620289006551040" }

  let(:twitter_owner) do
    {
      twitter_owner_id => {
        "id" => twitter_owner_id,
        "name" => "Bot Owner",
        "screen_name" => "botowner"
      }
    }
  end

  let(:twitter_user_data) do
    {
      twitter_user_id => {
        "id" => twitter_user_id,
        "name" => "Test User",
        "screen_name" => "testuser"
      }
    }
  end

  let(:pkg) do
    AppPackagesCatalog.update_all
    allow_any_instance_of(AppPackageIntegration).to receive(:handle_registration).and_return({})
    app.app_package_integrations.create(
      api_secret: "secret",
      api_key: "key",
      access_token: "token",
      access_token_secret: "token_secret",
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

  def message_for(sender_id, recipient_id, message_data = {}, message_id = "1")
    {
      "type" => "message_create",
      "id" => message_id,
      "created_timestamp" => "1579118212009",
      "message_create" => {
        "target" => { "recipient_id" => recipient_id },
        "sender_id" => sender_id,
        "message_data" => { "text" => "hello" }.merge(message_data)
      }
    }
  end

  def event_params(events, for_user_id: twitter_owner_id)
    {
      "for_user_id" => for_user_id,
      "direct_message_events" => events,
      "users" => twitter_owner.merge(twitter_user_data)
    }
  end

  describe "process_event" do
    before { pkg }

    it "returns nil when params have no direct_message_events key" do
      result = api.process_event({ "other_key" => "value" }, pkg)
      expect(result).to be_nil
      expect(app.conversations.count).to eq(0)
    end

    it "creates a conversation for an incoming DM from a user" do
      params = event_params([message_for(twitter_user_id, twitter_owner_id)])
      api.process_event(params, pkg)

      expect(app.conversations.count).to eq(1)
      conv = app.conversations.first
      expect(conv.messages.count).to eq(1)
      channel = conv.conversation_channels.find_by(provider: "twitter")
      expect(channel).to be_present
      expect(channel.provider_channel_id).to eq(twitter_user_id)
    end

    it "uses the target as channel when the bot is the sender (outgoing direction)" do
      params = event_params([message_for(twitter_owner_id, twitter_user_id)])
      api.process_event(params, pkg)

      expect(app.conversations.count).to eq(1)
      channel = app.conversations.first.conversation_channels.find_by(provider: "twitter")
      expect(channel.provider_channel_id).to eq(twitter_user_id)
    end

    it "attributes the message to the agent when the bot is the sender" do
      params = event_params([message_for(twitter_owner_id, twitter_user_id)])
      api.process_event(params, pkg)

      msg = app.conversations.first.messages.last
      expect(msg.authorable).to be_a(Agent)
    end

    it "attributes the message to the participant when the user is the sender" do
      params = event_params([message_for(twitter_user_id, twitter_owner_id, {}, "10")])
      api.process_event(params, pkg)

      msg = app.conversations.first.messages.last
      expect(msg.authorable).to be_an(AppUser)
    end

    it "skips a duplicate and adds a new message in the same batch" do
      params = event_params([
                              message_for(twitter_user_id, twitter_owner_id, {}, "42"),
                              message_for(twitter_user_id, twitter_owner_id, { "text" => "second" }, "42"),
                              message_for(twitter_user_id, twitter_owner_id, { "text" => "new one" }, "99")
                            ])
      api.process_event(params, pkg)

      expect(app.conversations.count).to eq(1)
      conversation = app.conversations.first
      expect(conversation.messages.count).to eq(2)
      expect(conversation.conversation_part_channel_sources.pluck(:message_source_id))
        .to contain_exactly("42", "99")
    end

    it "creates an external_profile for a new twitter user" do
      params = event_params([message_for(twitter_user_id, twitter_owner_id)])
      api.process_event(params, pkg)

      profile = app.external_profiles.find_by(provider: "twitter", profile_id: twitter_user_id)
      expect(profile).to be_present
      expect(profile.app_user).to be_present
    end

    it "stores the text and serialized_content on the message" do
      params = event_params([message_for(twitter_user_id, twitter_owner_id, { "text" => "hi there" })])
      api.process_event(params, pkg)

      msg = app.conversations.first.messages.last.messageable
      expect(msg.html_content).to eq("hi there")
      expect(msg.serialized_content).to be_present
    end
  end

  describe "send_message" do
    let(:participant) do
      p = app.add_anonymous_user(properties: { name: "Twitter User" })
      p.external_profiles.create(provider: "twitter", profile_id: twitter_user_id)
      p.properties = p.properties.merge("twitter_id" => twitter_user_id)
      p.save!
      p
    end

    let(:conversation) do
      app.conversations.create(
        main_participant: participant,
        conversation_channels_attributes: [
          { provider: "twitter", provider_channel_id: twitter_user_id }
        ]
      )
    end

    before do
      pkg
      allow(ApiChannelNotificatorJob).to receive(:perform_later)
    end

    def build_part(conversation, from:, html_content:, serialized_content:, private_note: false)
      part = conversation.process_message_part(
        from: from,
        message: { html_content: html_content, serialized_content: serialized_content },
        private_note: private_note
      )
      part.save!
      part
    end

    def expect_dm_request(twitter_api, text:, attachment: nil)
      message_data = { text: text }
      message_data[:attachment] = attachment if attachment
      expected = {
        event: {
          type: "message_create",
          message_create: { target: { recipient_id: twitter_user_id }, message_data: message_data }
        }
      }
      expect(twitter_api).to have_received(:post).with(
        "/1.1/direct_messages/events/new.json",
        expected.to_json,
        { "content-type" => "application/json" }
      ).once
    end

    it "returns nil for a private note without making any request" do
      sc = { type: "doc", content: [{ type: "paragraph", content: [{ type: "text", text: "secret" }] }] }.to_json
      part = build_part(conversation, from: participant, html_content: "secret", serialized_content: sc, private_note: true)

      result = api.send_message(conversation, part)
      expect(result).to be_nil
    end

    it "sends the full DM JSON for text-only content" do
      sc = { type: "doc", content: [{ type: "paragraph", content: [{ type: "text", text: "hello" }] }] }.to_json
      part = build_part(conversation, from: agent, html_content: "hello", serialized_content: sc)

      twitter_api = double("twitter_api")
      api.instance_variable_set(:@twitter_api, twitter_api)

      dm_response = double("response", code: "200", body: '{"event":{"id":"123"}}')
      allow(twitter_api).to receive(:post).and_return(dm_response)

      api.send_message(conversation, part)

      expect_dm_request(twitter_api, text: "hello")
    end

    it "attaches the first image when two ImageBlocks are present" do
      sc = {
        type: "doc",
        content: [
          { type: "paragraph", content: [{ type: "text", text: "check this" }] },
          { type: "ImageBlock", attrs: { url: "https://cdn.example.com/first.png", caption: "check this" } },
          { type: "ImageBlock", attrs: { url: "https://cdn.example.com/second.png", caption: "also this" } }
        ]
      }.to_json

      part = build_part(conversation, from: agent, html_content: "check this", serialized_content: sc)

      twitter_api = double("twitter_api")
      media_api = double("media_api")
      api.instance_variable_set(:@twitter_api, twitter_api)
      api.instance_variable_set(:@twitter_media_api, media_api)

      allow(MessageApis::SafeDownload).to receive(:fetch)
        .and_return(StringIO.new("\x89PNG\r\n\x1A\n#{"\x00" * 32}".b))
      allow(MessageApis::BlockManager).to receive(:absolute_url)
        .and_call_original
      allow(MessageApis::BlockManager).to receive(:absolute_url)
        .with("https://cdn.example.com/first.png")
        .and_return("https://cdn.example.com/first.png")

      init_resp = double(code: "200", body: { "media_id" => 99, "media_id_string" => "99" }.to_json)
      append_resp = double(code: "200", body: { "media_id" => 99 }.to_json)
      finalize_resp = double(code: "200", body: { "media_id" => 99, "media_id_string" => "99" }.to_json)

      allow(media_api).to receive(:post)
        .with("/1.1/media/upload.json", hash_including(command: "INIT"), anything)
        .and_return(init_resp)
      allow(media_api).to receive(:post)
        .with("/1.1/media/upload.json", hash_including(command: "APPEND"), anything)
        .and_return(append_resp)
      allow(media_api).to receive(:post)
        .with("/1.1/media/upload.json", hash_including(command: "FINALIZE"), anything)
        .and_return(finalize_resp)

      dm_response = double(code: "200", body: '{"event":{"id":"456"}}')
      allow(twitter_api).to receive(:post).and_return(dm_response)

      api.send_message(conversation, part)

      expect_dm_request(twitter_api, text: "check this", attachment: { type: "media", media: { id: "99" } })
      expect(MessageApis::SafeDownload).to have_received(:fetch).with("https://cdn.example.com/first.png").once
      expect(MessageApis::SafeDownload).not_to have_received(:fetch).with("https://cdn.example.com/second.png")
    end

    it "sends without attachment when upload returns no data" do
      sc = {
        type: "doc",
        content: [
          { type: "paragraph", content: [{ type: "text", text: "no image" }] },
          { type: "ImageBlock", attrs: { url: "https://cdn.example.com/missing.png", caption: "no image" } }
        ]
      }.to_json

      part = build_part(conversation, from: agent, html_content: "no image", serialized_content: sc)

      twitter_api = double("twitter_api")
      api.instance_variable_set(:@twitter_api, twitter_api)

      allow(MessageApis::SafeDownload).to receive(:fetch).and_return(nil)
      allow(MessageApis::BlockManager).to receive(:absolute_url)
        .and_call_original
      allow(MessageApis::BlockManager).to receive(:absolute_url)
        .with("https://cdn.example.com/missing.png")
        .and_return("https://cdn.example.com/missing.png")

      dm_response = double(code: "200", body: '{"event":{"id":"789"}}')
      allow(twitter_api).to receive(:post).and_return(dm_response)

      api.send_message(conversation, part)

      expect_dm_request(twitter_api, text: "no image")
    end
  end
end
