# frozen_string_literal: true

require "rails_helper"

class SuccessMock
  attr_accessor :body

  def success?
    true
  end
end

RSpec.describe Api::V1::Hooks::ProviderController, type: :controller do
  let(:owner_phone) do
    "whatsapp:+1111"
  end

  let(:user_phone) do
    "whatsapp:+2222"
  end

  let(:serialized) do
    {
      type: "doc",
      content: [{ type: "paragraph", content: [{ type: "text", text: "foobar" }] }]
    }.to_json
  end

  def data_for(id:, sender:, recipient:, message_id: nil, message_data: {})
    {
      "SmsMessageSid" => message_id,
      "NumMedia" => "0",
      "SmsSid" => message_id,
      "SmsStatus" => "received",
      "Body" => message_data.blank? ? "hola" : message_data["text"],
      "To" => recipient,
      "NumSegments" => "1",
      "MessageSid" => message_id,
      "AccountSid" => "ACe290",
      "From" => sender,
      "ApiVersion" => "2010-04-01",
      "controller" => "api/v1/hooks/provider",
      "action" => "process_event",
      "provider" => "twilio",
      "app_key" => app.key,
      "id" => @pkg.encoded_id
    }
  end

  def data_for_media(id:, sender:, recipient:, message_id: nil, message_data: {})
    {
      "MediaContentType0" => "image/jpeg",
      "SmsMessageSid" => message_id,
      "NumMedia" => "1",
      "SmsSid" => message_id,
      "SmsStatus" => "received",
      "Body" => "",
      "To" => "whatsapp:+1111",
      "NumSegments" => "1",
      "MessageSid" => message_id,
      "AccountSid" => "ACe290",
      "From" => "whatsapp:+2222",
      "MediaUrl0" => "https://api.twilio.com/2010-04-01/Accounts/AAAA/Messages/AAAAAAAAA/Media/MEf98b16d258dbb7380e44996a3337c54c",
      "ApiVersion" => "2010-04-01",
      "action" => "process_event",
      "provider" => "twilio",
      "controller" => "api/v1/hooks/provider",
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
    AppPackage.find_by(name: "Twilio")
  end

  describe "hooks" do
    before do
      AppPackagesCatalog.update_all
    end
    before :each do
      ActiveJob::Base.queue_adapter = :test
      ActiveJob::Base.queue_adapter.perform_enqueued_at_jobs = false

      allow_any_instance_of(AppPackageIntegration).to receive(:handle_registration)
        .and_return({})

      @pkg = app.app_package_integrations.create(
        {
          app_package: app_package,
          settings: {
            api_secret: "aaa",
            api_key: "aaa",
            user_id: owner_phone,
            new_conversations_after: 1
          }
        }
      )
    end

    it "acknowledges status callbacks for an unknown attachment SID" do
      %w[undelivered read].each do |status|
        params = data_for(id: @pkg.id, sender: user_phone, recipient: owner_phone, message_id: "SM-untracked")
        perform_enqueued_jobs do
          post :process_event, params: params.merge("SmsStatus" => status)
        end

        expect(response).to have_http_status(:ok)
        expect(app.conversations).to be_empty
      end
    end

    it "receive conversation data" do
      get(:process_event,
          params: data_for(
            id: @pkg.id,
            sender: owner_phone,
            recipient: user_phone,
            message_id: "1234"
          ))
      perform_enqueued_jobs
      expect(response.status).to be == 200
      expect(app.conversations.count).to be == 1
      expect(app.conversations.last.messages).to be_any
      expect(app.conversations.last.messages.last.conversation_part_channel_sources).to be_any
    end

    it "receive conversation media" do
      get(:process_event,
          params: data_for_media(
            id: @pkg.id,
            sender: owner_phone,
            recipient: user_phone,
            message_id: "1234"
          ))
      perform_enqueued_jobs
      expect(response.status).to be == 200
      expect(app.conversations.count).to be == 1
      expect(app.conversations.last.messages).to be_any

      message = app.conversations.last.messages.last
      expect(message.conversation_part_channel_sources).to be_any
      expect(message.messageable.serialized_content).to include("https://api.twilio.com/")
    end

    it "receive two messages in single conversation" do
      expect(app.app_users).to be_empty

      get(:process_event, params: data_for(
        id: @pkg.id,
        sender: user_phone,
        recipient: owner_phone,
        message_id: "1234"
      ))
      perform_enqueued_jobs

      expect(app.app_users.size).to be == 1

      get(:process_event, params: data_for(
        id: @pkg.id,
        sender: user_phone,
        recipient: owner_phone,
        message_id: "1235"
      ))
      perform_enqueued_jobs

      expect(app.app_users.size).to be == 1

      expect(response.status).to be == 200
      expect(app.conversations.count).to be == 1
      expect(app.conversations.first.messages.count).to be == 2
    end

    it "reply from agent on twilio" do
      get(:process_event, params: data_for(
        id: @pkg.id,
        sender: user_phone,
        recipient: owner_phone,
        message_id: 1
      ))

      get(:process_event, params: data_for(
        id: @pkg.id,
        sender: owner_phone,
        recipient: user_phone,
        message_id: 2
      ))
      perform_enqueued_jobs

      expect(response.status).to be == 200
      expect(app.conversations.count).to be == 1
      expect(app.conversations.first.messages.count).to be == 2
      expect(app.conversations.first.messages.last.authorable).to be_a(Agent)
    end

    it "receive text with breakline" do
      get(:process_event, params: data_for(
        id: @pkg.id,
        sender: user_phone,
        recipient: owner_phone,
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

    describe "process message" do
      before :each do
        get(:process_event,
            params: data_for(
              id: @pkg.id,
              sender: owner_phone,
              recipient: user_phone,
              message_id: "1234"
            ))
        perform_enqueued_jobs
      end

      it "#send_message, create message from conversation" do
        opts = {
          from: Agent.first,
          message: {
            serialized_content: serialized,
            html_content: "message"
          }
        }

        body = {}.to_json
        success_mock = SuccessMock.new
        success_mock.body = body

        expect_any_instance_of(Faraday::Connection).to receive(:post).and_return(
          success_mock
        )

        Conversation.last.add_message(opts)
        perform_enqueued_jobs
      end

      it "#send_message, create message from conversation" do
        opts = {
          private_note: true,
          from: Agent.first,
          message: {
            serialized_content: { blocks: [] }.to_json,
            html_content: "message"
          }
        }

        expect_any_instance_of(Faraday::Connection).to_not receive(:post)

        Conversation.last.add_message(opts)
        perform_enqueued_jobs
      end
    end

    describe "thread slicing" do
      it "second message will create a new conversation when time is up" do
        expect(app.app_users).to be_empty

        get(:process_event, params: data_for(
          id: @pkg.id,
          sender: user_phone,
          recipient: owner_phone,
          message_id: "1234"
        ))
        perform_enqueued_jobs

        expect(app.app_users.size).to be == 1

        allow_any_instance_of(Conversation).to receive(:latest_user_visible_comment_at)
          .and_return(10.hours.ago)

        get(:process_event, params: data_for(
          id: @pkg.id,
          sender: user_phone,
          recipient: owner_phone,
          message_id: "1235"
        ))
        perform_enqueued_jobs

        expect(app.app_users.size).to be == 1

        expect(response.status).to be == 200
        expect(app.conversations.count).to be == 2
        expect(app.conversations.first.messages.count).to be == 1
        expect(app.conversations.last.messages.count).to be == 1
        expect(app.conversations.first).to be_closed
        expect(app.conversations.first.conversation_channels).to be_empty
      end

      it "second message will be kept in same conversation when in time" do
        expect(app.app_users).to be_empty

        get(:process_event, params: data_for(
          id: @pkg.id,
          sender: user_phone,
          recipient: owner_phone,
          message_id: "1234"
        ))
        perform_enqueued_jobs

        expect(app.app_users.size).to be == 1

        allow_any_instance_of(Conversation).to receive(:latest_user_visible_comment_at)
          .and_return(10.minutes.ago)

        get(:process_event, params: data_for(
          id: @pkg.id,
          sender: user_phone,
          recipient: owner_phone,
          message_id: "1235"
        ))
        perform_enqueued_jobs

        expect(app.app_users.size).to be == 1

        expect(response.status).to be == 200
        expect(app.conversations.count).to be == 1
        expect(app.conversations.first.messages.count).to be == 2
        expect(app.conversations.first).to be_opened
        expect(app.conversations.first.conversation_channels).to be_present
      end

      it "second message will create a new conversation if current convo is closed" do
        expect(app.app_users).to be_empty

        get(:process_event, params: data_for(
          id: @pkg.id,
          sender: user_phone,
          recipient: owner_phone,
          message_id: "1234"
        ))
        perform_enqueued_jobs

        expect(app.app_users.size).to be == 1

        app.conversations.first.close!

        get(:process_event, params: data_for(
          id: @pkg.id,
          sender: user_phone,
          recipient: owner_phone,
          message_id: "1235"
        ))

        perform_enqueued_jobs

        expect(app.app_users.size).to be == 1

        expect(response.status).to be == 200
        expect(app.conversations.count).to be == 2
        expect(app.conversations.first.messages.count).to be == 1
        expect(app.conversations.last.messages.count).to be == 1
        expect(app.conversations.first).to be_closed
        expect(app.conversations.first).to be_blocked
        expect(app.conversations.first.blocked_reason).to_not be_blank
        expect(app.conversations.first.conversation_channels).to be_empty
      end
    end
  end

  describe "Twilio outgoing messages" do
    include WebMock::API

    around do |example|
      WebMock.enable!
      example.run
    ensure
      WebMock.reset!
      WebMock.disable!
    end

    let(:api) { MessageApis::Twilio::Api.new(config: { "api_key" => "test-sid", "api_secret" => "test-token", "user_id" => owner_phone }) }
    let(:endpoint) { "https://api.twilio.com/2010-04-01/Accounts/test-sid/Messages.json" }
    let(:recipient) { app.add_user(email: "recipient@example.com") }
    let(:thread) { app.conversations.create!(main_participant: recipient) }

    before do
      recipient.external_profiles.create!(provider: "twilio", profile_id: user_phone)
    end

    def deliver(content)
      part = thread.messages.build(authorable: agent_role.agent, messageable: ConversationPartContent.new(content))
      api.send_message(thread, part)
    end

    def expect_delivery(text)
      stub = stub_request(:post, endpoint).with(headers: { "Authorization" => "Basic #{Base64.strict_encode64('test-sid:test-token')}" }) do |request|
        Rack::Utils.parse_query(request.body)["Body"] == text
      end
      stub.to_return(status: 200, body: "{}")
    end

    it "sends the outgoing Dante paragraph to the provider" do
      stub = expect_delivery("foobar")
      doc = { type: "doc", content: [{ type: "paragraph", content: [{ type: "text", text: "foobar" }] }] }
      deliver(serialized_content: doc.to_json)
      assert_requested(stub)
    end

    context "when notifying a saved message" do
      let(:images) { %w[first second third].map { |name| ["ImageBlock", "https://cdn.example.com/#{name}.png"] } }

      def saved_part(text, media)
        blocks = [{ type: "text", text: text }] + media.map { |type, url| { type: type, attrs: { url: url } } }
        thread.add_message(from: agent_role.agent, message: { serialized_content: { content: blocks }.to_json })
      end

      def notify(part)
        api.notify_message(conversation: thread, part: part, channel: user_phone)
      end

      def delivery_errors
        thread.messages.where(messageable_type: "ConversationPartEvent").map(&:messageable)
              .select { |event| event.action.start_with?("errored:") }
      end

      def success_response(sid)
        { status: 201, body: { sid: sid }.to_json }
      end

      it "emits one safe event for a partial failure" do
        error = { code: 21_620, message: "Invalid  media\nhttps://cdn.example.com/second.png #{'x' * 250}",
                  more_info: "https://www.twilio.com/docs/errors/21620" }
        stub_request(:post, endpoint).to_return(
          success_response("SM1"), { status: 400, body: error.to_json }, success_response("SM3")
        )
        part = saved_part("Caption", images)

        notify(part)

        expect(delivery_errors.size).to eq(1)
        event = delivery_errors.first
        data = event.data
        expect(data.keys).to contain_exactly("status", "code", "message")
        expect(data).to include("status" => 400, "code" => 21_620)
        expect(data.fetch("message")).to start_with("Invalid media [url] ")
        expect(data.fetch("message")).not_to include("https://")
        expect(data.fetch("message").length).to be <= 200
        expect(event.action).to eq("errored: #{data.fetch('message')}")
        expect(part.conversation_part_channel_sources.pluck(:message_source_id)).to contain_exactly("SM1", "SM3")
      end

      it "stores only safe fields from an undelivered status callback" do
        part = saved_part("Caption", [])
        part.conversation_part_channel_sources.create!(provider: "twilio", message_source_id: "SM2")

        api.process_event({ "SmsStatus" => "undelivered", "SmsSid" => "SM2", "ErrorCode" => "30008",
                            "id" => "callback", "To" => user_phone, "MediaUrl0" => images.first.last }, nil)

        expect(delivery_errors.map(&:data)).to eq([{ "status" => nil, "code" => "30008", "message" => "undelivered" }])
      end

      it "reports a single failed media request once (base-green)" do
        stub = stub_request(:post, endpoint).to_return(status: 400, body: { message: "Rejected image" }.to_json)

        notify(saved_part("", images.first(1)))

        assert_requested(stub, times: 1)
        expect(delivery_errors.map(&:action)).to eq(["errored: Rejected image"])
      end

      it "does not resend the separate text after audio and text were accepted (base-green)" do
        stub = stub_request(:post, endpoint).to_return(success_response("SM1"), success_response("SM2"))
        part = saved_part("Voice caption", [["AudioRecorderBlock", "https://cdn.example.com/voice.ogg"]])

        2.times { notify(part) }

        assert_requested(stub, times: 2)
      end

      it "does not resend a single text after it was accepted (base-green)" do
        stub = stub_request(:post, endpoint).to_return(success_response("SM1"))
        part = saved_part("Hello", [])

        2.times { notify(part) }

        assert_requested(stub, times: 1)
      end

      it "does not send an incoming audio part back to the provider" do
        media = [["AudioRecorderBlock", "https://cdn.example.com/voice.ogg"]]
        block = { type: media.first.first, attrs: { url: media.first.last } }
        part = thread.add_message(
          from: recipient,
          message: { serialized_content: { content: [{ type: "text", text: "Voice caption" }, block] }.to_json },
          provider: "twilio",
          message_source_id: "SM-inbound"
        )
        stub = stub_request(:post, endpoint).to_return(success_response("SM-duplicate"))

        notify(part)

        assert_not_requested(stub)
      end

      it "leaves a part to the job already sending it" do
        part = saved_part("Caption", images.first(1))
        first_request = Queue.new
        finish_request = Queue.new
        first_request_token = Queue.new
        first_request_token << true
        stub = stub_request(:post, endpoint).to_return do
          unless first_request_token.empty?
            first_request_token.pop
            first_request << true
            finish_request.pop
          end
          success_response("SM1")
        end

        sender = Thread.new { notify(part) }
        Timeout.timeout(5) do
          first_request.pop
          notify(ConversationPart.find(part.id))
        end
        finish_request << true
        sender.value

        assert_requested(stub, times: 1)
      ensure
        finish_request << true if finish_request && sender&.alive?
        sender&.join(5)
      end

      it "deduplicates callbacks per SID and keeps errors for other SIDs in the same integration" do
        part = saved_part("Caption", [])
        %w[SM1 SM2].each do |sid|
          part.conversation_part_channel_sources.create!(provider: "twilio", message_source_id: sid)
        end
        callback = { "SmsStatus" => "undelivered", "id" => "integration" }

        %w[SM1 SM1 SM2].each { |sid| api.process_event(callback.merge("SmsSid" => sid), nil) }

        expect(delivery_errors.map(&:action)).to eq(["errored: undelivered", "errored: undelivered"])
      end

      it "ignores statuses without a SID even if an outgoing source has no provider id" do
        part = saved_part("Caption", [])
        part.conversation_part_channel_sources.create!(provider: "twilio", delivery_index: 0)

        api.process_event({ "SmsStatus" => "read" }, nil)
        api.process_event({ "SmsStatus" => "undelivered", "SmsSid" => "" }, nil)

        expect(part.reload.read_at).to be_nil
        expect(delivery_errors).to be_empty
      end
    end

    context "with media" do
      let(:requests) { [] }

      before do
        allow(Chaskiq::Config).to receive(:get).and_call_original
        allow(Chaskiq::Config).to receive(:get).with("HOST").and_return("https://chat.example.com")

        stub_request(:post, endpoint).to_return do |request|
          requests << Rack::Utils.parse_query(request.body)
          { status: 201, body: { sid: "SM#{requests.size}" }.to_json }
        end
      end

      def deliver_media(text, media)
        nodes = [{ type: "text", text: text }]
        media.each { |type, url| nodes << { type: type, attrs: { url: url } } }
        deliver(serialized_content: { type: "doc", content: nodes }.to_json)
      end

      it "sends every attachment in order and includes the caption once" do
        result = deliver_media("Here are the files", [
                                 ["ImageBlock", "/uploads/first image.png"],
                                 ["VideoBlock", "https://cdn.example.com/video.mp4"],
                                 ["FileBlock", "/uploads/file.pdf"],
                                 ["AudioRecorderBlock", "/uploads/voice.ogg"]
                               ])

        expect(requests.map { |request| request.fetch("MediaUrl") }).to eq([
                                                                             "https://chat.example.com/uploads/first%20image.png",
                                                                             "https://cdn.example.com/video.mp4",
                                                                             "https://chat.example.com/uploads/file.pdf",
                                                                             "https://chat.example.com/uploads/voice.ogg"
                                                                           ])
        expect(requests.pluck("Body")).to eq(["Here are the files", nil, nil, nil])
        expect(requests.pluck("To").uniq).to eq([user_phone])
        expect(JSON.parse(result.body)).to eq("sid" => "SM1")
      end

      it "sends audio without a caption and posts the text separately" do
        deliver_media("Listen to this", [["AudioRecorderBlock", "/uploads/voice.ogg"]])

        expect(requests.map { |request| request.slice("MediaUrl", "Body") }).to eq([
                                                                                     { "MediaUrl" => "https://chat.example.com/uploads/voice.ogg" },
                                                                                     { "Body" => "Listen to this" }
                                                                                   ])
      end

      it "sends a standalone Body after video, document, WebP and audio attachments" do
        deliver_media("Caption as a message", [
                        ["VideoBlock", "/uploads/video.mp4"],
                        ["FileBlock", "/uploads/file.pdf"],
                        ["ImageBlock", "/uploads/sticker.webp?download=photo.png"],
                        ["AudioRecorderBlock", "/uploads/voice.ogg"]
                      ])

        expect(requests.map { |request| request.slice("MediaUrl", "Body") }).to eq([
                                                                                     { "MediaUrl" => "https://chat.example.com/uploads/video.mp4" },
                                                                                     { "MediaUrl" => "https://chat.example.com/uploads/file.pdf" },
                                                                                     { "MediaUrl" => "https://chat.example.com/uploads/sticker.webp?download=photo.png" },
                                                                                     { "MediaUrl" => "https://chat.example.com/uploads/voice.ogg" },
                                                                                     { "Body" => "Caption as a message" }
                                                                                   ])
      end

      it "uses the first supported image for the caption after ineligible attachments" do
        deliver_media("Photo caption", [
                        ["ImageBlock", "/uploads/sticker.webp"],
                        ["ImageBlock", "/uploads/photo.JPEG?download=1"],
                        ["ImageBlock", "/uploads/another.png"]
                      ])

        expect(requests.pluck("Body")).to eq([nil, "Photo caption", nil])
      end
    end
  end
end
