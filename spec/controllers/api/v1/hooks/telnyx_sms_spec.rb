require "rails_helper"

RSpec.describe Api::V1::Hooks::ProviderController, type: :controller do
  include ActiveJob::TestHelper

  let(:owner_phone) do
    "1111"
  end

  let(:user_phone) do
    "2222"
  end

  def data_for(id:, sender:, message_id: nil, message_data: {})
    {
      data: {
        event_type: "message.received",
        id: "d1fedd34-0cc8-4056-b11a-c3d037364264",
        occurred_at: "2022-02-17T18:21:44.826+00:00",
        payload: {
          cc: [],
          completed_at: nil,
          cost: nil,
          direction: "inbound",
          encoding: "UCS-2",
          errors: [],
          from: {
            carrier: "",
            line_type: "",
            phone_number: sender # "+56992302305"
          },
          id: message_id,
          media: [],
          messaging_profile_id: "xxxxxxxxxx",
          organization_id: "xxxxxxxx",
          parts: 1,
          received_at: "2022-02-17T18:21:44.551+00:00",
          record_type: "message",
          sent_at: nil,
          subject: "",
          tags: [],
          text: message_data["text"] || "hey!",
          to: [
            {
              carrier: "Telnyx",
              line_type: "Wireless",
              phone_number: "+5611111111",
              status: "webhook_delivered"
            }
          ],
          type: "SMS",
          valid_until: nil,
          webhook_failover_url: nil,
          webhook_url: "http://www.wwwebhook.co/hook/bogus"
        },
        record_type: "event"
      },
      meta: {
        attempt: 1,
        delivered_to: "http://www.wwwebhook.co/hook/bogus"
      },

      "controller" => "api/v1/hooks/provider",
      "action" => "process_event",
      "provider" => "telnyx_sms",
      "app_key" => app.key,
      "id" => @pkg.encoded_id
    }
  end

  let!(:app) do
    FactoryBot.create(:app)
  end

  let!(:agent_role) do
    app.add_agent({ email: "test2@test.cl" })
  end

  let(:app_package) do
    AppPackage.find_by(name: "TelnyxSms")
  end

  describe "hooks" do
    before do
      AppPackagesCatalog.update_all
    end
    before :each do
      ActiveJob::Base.queue_adapter = :test
      ActiveJob::Base.queue_adapter.perform_enqueued_at_jobs = false

      AppPackageIntegration.any_instance
                           .stub(:handle_registration)
                           .and_return({})

      @pkg = app.app_package_integrations.create(
        app_package: app_package,
        settings: {
          api_key: "aaa",
          profile_id: owner_phone,
          phones: "+56-2-2914-1453,+1-513-203-1070,+1-573-103-7079"
        }
      )
    end

    it "receive conversation data" do
      get(:process_event,
          params: data_for(id: @pkg.id,
                           sender: owner_phone,
                           message_id: "1234"))
      perform_enqueued_jobs
      expect(response.status).to be == 200
      expect(app.conversations.count).to be == 1
      expect(app.conversations.last.messages).to be_any
      # expect(app.conversations.last.main_participant.name).to eql("Miguel Michelson")
      expect(app.conversations.last.messages.last.conversation_part_channel_sources).to be_any
    end

    it "receive two messages in single conversation" do
      expect(app.app_users).to be_empty

      get(:process_event, params: data_for(
        id: @pkg.id,
        sender: user_phone,
        message_id: "1234"
      ))
      perform_enqueued_jobs

      expect(app.app_users.size).to be == 1

      get(:process_event, params: data_for(
        id: @pkg.id,
        sender: user_phone,
        message_id: "1235"
      ))
      perform_enqueued_jobs

      expect(app.app_users.size).to be == 1

      expect(response.status).to be == 200
      expect(app.conversations.count).to be == 1
      expect(app.conversations.first.messages.count).to be == 2
    end

    it "receive text with breakline" do
      get(:process_event, params: data_for(
        id: @pkg.id,
        sender: user_phone,
        message_data: {
          "text" => "one\ntwo\ntree\n✌️"
        }
      ))
      perform_enqueued_jobs

      message = app.conversations.first.messages.first.messageable

      expect(message.html_content).to be == "one\ntwo\ntree\n✌️"
      expect(message.serialized_content).to be_present

      blocks = MessageApis::BlockManager.get_blocks(message.serialized_content)

      expect(blocks.size).to be == 4
    end

    it "receive text with STOP" do
      get(:process_event, params: data_for(
        id: @pkg.id,
        sender: user_phone,
        message_data: {
          "text" => "STOP"
        }
      ))
      perform_enqueued_jobs

      message = app.conversations.first.messages.first.messageable

      expect(message.html_content).to be == "STOP"
      expect(message.serialized_content).to be_present

      blocks = MessageApis::BlockManager.get_blocks(message.serialized_content)

      expect(blocks.size).to be == 1

      expect(Conversation.last).to be_closed
    end

    it "outbound phone resolve" do
      klass = AppPackageIntegration.last.message_api_klass
      expect(klass.resolve_outbound_phone("+56xxxxx")[:from]).to start_with("+56")
      expect(klass.resolve_outbound_phone("+16xxxxx")[:from]).to start_with("+1")
    end
  end

  describe "TelnyxSms outgoing messages" do
    include WebMock::API

    around do |example|
      WebMock.enable!
      example.run
    ensure
      WebMock.reset!
      WebMock.disable!
    end

    let(:api) { MessageApis::TelnyxSms::Api.new(config: { api_key: "test-key", package: double(settings: { "phones" => "" }) }) }
    let(:endpoint) { "https://api.telnyx.com/v2/messages" }
    let(:recipient) { app.add_user(email: "recipient@example.com") }
    let(:thread) { app.conversations.create!(main_participant: recipient) }

    before do
      thread.conversation_channels.create!(provider: "TelnyxSms", provider_channel_id: "123")
    end

    def deliver(content)
      part = thread.messages.build(authorable: agent_role.agent, messageable: ConversationPartContent.new(content))
      api.send_message(thread, part)
    end

    def expect_delivery(text)
      stub = stub_request(:post, endpoint).with(headers: { "Authorization" => "Bearer test-key" }) do |request|
        JSON.parse(request.body)["text"] == text
      end
      stub.to_return(status: 200, body: "{}")
    end

    it "sends the outgoing Dante paragraph to the provider" do
      stub = expect_delivery("foobar")
      doc = { type: "doc", content: [{ type: "paragraph", content: [{ type: "text", text: "foobar" }] }] }
      2.times { deliver(serialized_content: doc.to_json) }
      assert_requested(stub, times: 2)
    end

    it "sends text from the legacy blocks wrapper" do
      stub = expect_delivery("forwarded text")
      legacy = { blocks: [{ type: "text", text: "forwarded text" }], entityMap: {} }
      deliver(serialized_content: legacy.to_json)
      assert_requested(stub)
    end

    it "sends HTML-only content as plain text" do
      stub = expect_delivery("Hello & goodbye")
      deliver(html_content: "<p><b>Hello</b> &amp; goodbye</p>")
      assert_requested(stub)
    end

    it "makes no request for an empty outgoing message" do
      stub = stub_request(:post, endpoint).to_return(status: 200, body: "{}")
      deliver(serialized_content: "", html_content: "")
      assert_not_requested(stub)
    end
  end
end
