# frozen_string_literal: true

require "rails_helper"
require "webmock"
include ActiveJob::TestHelper

RSpec.describe Api::V1::Hooks::ProviderController, type: :controller do
  let(:owner_phone) do
    "1111"
  end

  let(:user_phone) do
    "2222"
  end

  def data_for(id:, sender:, message_id: nil, message_data: {})
    {
      messages: [
        {
          from: sender,
          id: message_id,
          text: {
            body: message_data.blank? ? "hola" : message_data["text"]
          },
          timestamp: "1612635177",
          type: "text"
        }
      ],
      contacts: [
        {
          profile: {
            name: "Miguel Michelson"
          },
          wa_id: "1111"
        }
      ],
      "controller" => "api/v1/hooks/provider",
      "action" => "process_event",
      "provider" => "dialog_360",
      "app_key" => app.key,
      "id" => @pkg.encoded_id
    }
  end

  def data_for_media(id:, sender:, message_id: nil, message_data: {})
    {

      contacts: [
        {
          profile: {
            name: "Miguel Michelson"
          },
          wa_id: "56992302305"
        }
      ],

      messages: [{
        from: sender,
        id: message_id,
        image: {
          file: "/usr/local/wamedia/shared/b1cf38-8734-4ad3-b4a1-ef0c10d0d683",
          id: "b1c68f38-8734-4ad3-b4a1-ef0c10d683",
          mime_type: "image/jpeg",
          sha256: "29ed500fa64eb55fc19dc4124acb300e5dcc54a0f822a301ae99944db",
          caption: "Check out my new phone!"
        },
        timestamp: "1521497954",
        type: "image"
      }],

      "controller" => "api/v1/hooks/provider",
      "action" => "process_event",
      "provider" => "dialog_360",
      "app_key" => app.key,
      "id" => @pkg.encoded_id
    }
  end

  def data_for_audio(id:, sender:, message_id: nil, message_data: {})
    {
      messages: [
        {
          from: sender,
          id: message_id,
          timestamp: "1612635177",
          type: "voice",
          voice: {
            file: "/usr/local/wamedia/shared/463e/b7ec/ff4e4d9bb1101879cbd411b2",
            id: "463eb7ec-ff4e-4d9b-b110-1879cbd411b2",
            mime_type: "audio/ogg; codecs=opus",
            sha256: "fa9e1807d936b7cebe63654ea3a7912b1fa9479220258d823590521ef53b0710"
          }
        }
      ],
      contacts: [
        {
          profile: {
            name: "Miguel Michelson"
          },
          wa_id: "56992302305"
        }
      ],
      "controller" => "api/v1/hooks/provider",
      "action" => "process_event",
      "provider" => "dialog_360",
      "app_key" => app.key,
      "id" => @pkg.encoded_id
    }
  end

  def data_for_video(id:, sender:, message_id: nil, message_data: {})
    {
      messages: [
        {
          from: sender,
          id: message_id,
          timestamp: "1612635177",
          type: "video",
          video: {
            file: "/usr/local/wamedia/shared/463e/b7ec/ff4e4d9bb1101879cbd411b2",
            id: "463eb7ec-ff4e-4d9b-b110-1879cbd411b2",
            mime_type: "audio/ogg; codecs=opus",
            sha256: "fa9e1807d936b7cebe63654ea3a7912b1fa9479220258d823590521ef53b0710"
          }
        }
      ],
      contacts: [
        {
          profile: {
            name: "Miguel Michelson"
          },
          wa_id: "56992302305"
        }
      ],
      "controller" => "api/v1/hooks/provider",
      "action" => "process_event",
      "provider" => "dialog_360",
      "app_key" => app.key,
      "id" => @pkg.encoded_id
    }
  end

  def data_for_errors(id:, sender:, message_id: nil, message_data: {})
    {
      statuses: [
        {
          errors: [
            {
              code: 470,
              href: "https://developers.facebook.com/docs/whatsapp/api/errors/",
              title: "Message failed to send because more than 24 hours have passed since the customer last replied to this number"
            }
          ],
          id: message_id,
          recipient_id: "56992302305",
          status: "failed",
          timestamp: "1616908033"
        }
      ],
      "controller" => "api/v1/hooks/provider",
      "action" => "process_event",
      "provider" => "dialog_360",
      "app_key" => app.key,
      "id" => id
    }
  end

  def data_for_read(id:, sender:, message_id: nil, message_data: {})
    {
      statuses: [
        {
          id: message_id,
          recipient_id: "56992302305",
          status: "delivered",
          timestamp: "1612646286"
        }
      ],
      "controller" => "api/v1/hooks/provider",
      "action" => "process_event",
      "provider" => "dialog_360",
      "app_key" => app.key,
      "id" => @pkg.encoded_id
    }
  end

  def data_for_sticker(id:, sender:, message_id: nil, message_data: {})
    {
      messages: [
        {
          from: sender,
          id: id,
          sticker: {
            id: "2d0eb523-84cd-4bec-ba73-9e06f0721918",
            metadata: {
              "android-app-store-link": "https://play.google.com/store/apps/details?id=com.dstukalov.walocalstoragestickers",
              "is-first-party-sticker": 0,
              "sticker-pack-id": "com.dstukalov.walocalstoragestickers.provider cc31886d051b823c638e2ee1e9d763f4",
              "sticker-pack-name": "Stickers",
              "sticker-pack-publisher": "You"
            },
            mime_type: "image/webp",
            sha256: "0a7d1c4ddac8547ee866f2b5366443ba8eddbc130acfaf7fc9b5d66a860f84f6"
          },
          timestamp: "1612664666",
          type: "sticker"
        }
      ],
      contacts: [
        {
          profile: {
            name: "Miguel Michelson"
          },
          wa_id: sender
        }
      ],
      "controller" => "api/v1/hooks/provider",
      "action" => "process_event",
      "provider" => "dialog_360",
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
    AppPackage.find_by(name: "Dialog360")
  end

  describe "Dialog360 outgoing messages" do
    include WebMock::API

    around do |example|
      WebMock.enable!
      example.run
    ensure
      WebMock.reset!
      WebMock.disable!
    end

    let(:api) { MessageApis::Dialog360::Api.new(config: { "api_key" => "test-key", "user_id" => owner_phone }) }
    let(:recipient) { app.add_user(email: "recipient@example.com") }
    let(:conversation) { app.conversations.create!(main_participant: recipient) }
    let(:requests) { [] }

    before do
      recipient.external_profiles.create!(provider: "dialog_360", profile_id: user_phone)
      allow(Chaskiq::Config).to receive(:get).and_call_original
      allow(Chaskiq::Config).to receive(:get).with("HOST").and_return("https://chat.example.com")

      stub_request(:post, "https://waba.360dialog.io/v1/messages").to_return do |request|
        requests << JSON.parse(request.body)
        { status: 201, body: { messages: [{ id: "wamid.#{requests.size}" }] }.to_json }
      end
    end

    def deliver_dialog_media(text, media)
      nodes = [{ type: "text", text: text }]
      media.each { |type, url| nodes << { type: type, attrs: { url: url } } }
      content = { type: "doc", content: nodes }.to_json
      part = conversation.messages.build(
        authorable: agent_role.agent,
        messageable: ConversationPartContent.new(serialized_content: content)
      )
      api.send_message(conversation, part)
    end

    it "sends every attachment in order with the caption on the first eligible request" do
      result = deliver_dialog_media("Here are the files", [
                                      ["AudioRecorderBlock", "/uploads/voice.ogg"],
                                      ["ImageBlock", "/uploads/first image.png"],
                                      ["VideoBlock", "https://cdn.example.com/video.mp4"],
                                      ["FileBlock", "/uploads/file.pdf"]
                                    ])

      expect(requests.pluck("type")).to eq(%w[audio image video document])
      expect(requests.map { |request| request.fetch(request.fetch("type")) }).to eq([
                                                                                      { "link" => "https://chat.example.com/uploads/voice.ogg" },
                                                                                      { "link" => "https://chat.example.com/uploads/first%20image.png", "caption" => "Here are the files" },
                                                                                      { "link" => "https://cdn.example.com/video.mp4" },
                                                                                      { "link" => "https://chat.example.com/uploads/file.pdf" }
                                                                                    ])
      expect(requests.pluck("to").uniq).to eq([user_phone])
      expect(JSON.parse(result.body)).to eq("messages" => [{ "id" => "wamid.1" }])
    end

    it "sends audio without a caption and posts the text separately" do
      deliver_dialog_media("Listen to this", [["AudioRecorderBlock", "/uploads/voice.ogg"]])

      expect(requests.map { |request| request.slice("type", "audio", "text") }).to eq([
                                                                                        { "type" => "audio", "audio" => { "link" => "https://chat.example.com/uploads/voice.ogg" } },
                                                                                        { "type" => "text", "text" => { "body" => "Listen to this" } }
                                                                                      ])
    end

    context "when notifying a saved message" do
      let(:endpoint) { "https://waba.360dialog.io/v1/messages" }
      let(:part) do
        images = %w[first second third].map { |name| { type: "ImageBlock", attrs: { url: "https://cdn.example.com/#{name}.png" } } }
        conversation.add_message(from: agent_role.agent, message: { serialized_content: { content: images }.to_json })
      end

      def notify
        api.notify_message(conversation: conversation, part: part, channel: user_phone)
      end

      def success_response(id)
        { status: 201, body: { messages: [{ id: id }] }.to_json }
      end

      def delivery_errors
        conversation.messages.where(messageable_type: "ConversationPartEvent").map(&:messageable)
                    .select { |event| event.action.start_with?("errored:") }
      end

      it "records a partial failure for rejected media" do
        error = { errors: [{ code: 1008, title: "Required parameter is missing" }] }
        stub_request(:post, endpoint).to_return(success_response("wamid.1"), { status: 400, body: error.to_json }, success_response("wamid.3"))

        notify

        expect(delivery_errors.map(&:data)).to eq([{ "status" => 400, "code" => 1008, "message" => "Required parameter is missing" }])
      end

      it "matches a failed status to a later provider id" do
        notify
        status = { "id" => "wamid.3", "status" => "failed", "errors" => [{ "code" => 470, "title" => "Re-engagement" }] }

        api.process_event({ "statuses" => [status] }, nil)

        expect(delivery_errors.map(&:action)).to eq(["errored: 470 Re-engagement"])
        expect(part.conversation_part_channel_sources.pluck(:message_source_id)).to contain_exactly("wamid.1", "wamid.2", "wamid.3")
      end

      it "keeps other ids when an accepted response has an empty messages array" do
        stub_request(:post, endpoint).to_return(
          { status: 201, body: { messages: [] }.to_json }, success_response("wamid.2"), success_response("wamid.3")
        )

        expect { notify }.not_to raise_error
        expect(part.conversation_part_channel_sources.pluck(:delivery_index, :message_source_id))
          .to contain_exactly([0, nil], [1, "wamid.2"], [2, "wamid.3"])
        api.process_event({ "statuses" => [{ "status" => "read" }, { "status" => "failed" }] }, nil)
        expect(part.reload.read_at).to be_nil
        expect(delivery_errors).to be_empty
      end

      it "does not resend the attachment accepted without an id before a timeout" do
        stub = stub_request(:post, endpoint)
               .to_return(status: 201, body: { messages: [] }.to_json)
               .then.to_raise(Faraday::TimeoutError)
               .then.to_return(success_response("wamid.2"), success_response("wamid.3"))

        expect { notify }.to raise_error(Faraday::TimeoutError)
        notify

        assert_requested(stub, times: 4)
        expect(part.conversation_part_channel_sources.pluck(:delivery_index, :message_source_id))
          .to contain_exactly([0, nil], [1, "wamid.2"], [2, "wamid.3"])
      end

      it "sanitizes the failed status event" do
        part.conversation_part_channel_sources.create!(provider: "dialog_360", message_source_id: "wamid.1")
        errors = [{ "code" => 470, "title" => "See https://example.com/why for details", "href" => "https://example.com/docs" }]

        api.process_event({ "statuses" => [{ "id" => "wamid.1", "status" => "failed", "errors" => errors }] }, nil)

        expect(delivery_errors.map(&:data)).to eq([{ "status" => nil, "code" => 470, "message" => "470 See [url] for details" }])
      end

      it "ignores object values in a failed status without rendering their contents" do
        part.conversation_part_channel_sources.create!(provider: "dialog_360", message_source_id: "wamid.1")
        errors = [{ "code" => { "phone" => "private-code" }, "title" => { "customer" => "private-title" } }]

        api.process_event({ "statuses" => [{ "id" => "wamid.1", "status" => "failed", "errors" => errors }] }, nil)

        expect(delivery_errors.map(&:action)).to eq(["errored: "])
        expect(delivery_errors.map(&:data)).to eq([{ "status" => nil, "code" => nil, "message" => "" }])
      end

      it "records the same failed status once and keeps distinct actions for its provider id" do
        part.conversation_part_channel_sources.create!(provider: "dialog_360", message_source_id: "wamid.1")
        status = { "id" => "wamid.1", "status" => "failed" }
        errors = [{ "code" => 470, "title" => "Re-engagement" }]
        replay = status.merge("errors" => errors)

        2.times { api.process_event({ "statuses" => [replay] }, nil) }
        api.process_event({ "statuses" => [status.merge("errors" => [{ "code" => 471, "title" => "Rejected" }])] }, nil)

        expect(delivery_errors.map(&:action)).to eq(["errored: 470 Re-engagement", "errored: 471 Rejected"])
      end

      it "holds a session lock and commits the status event before enqueuing notifications" do
        part.conversation_part_channel_sources.create!(provider: "dialog_360", message_source_id: "wamid.1")
        allow(ApiChannelNotificatorJob).to receive(:perform_later).and_wrap_original do |original, **args|
          visible = Thread.new { ConversationPart.exists?(args.fetch(:part_id)) }.value
          expect(visible).to be(true)
          ConversationPart.with_connection do |connection|
            expect(connection.transaction_open?).to be(false)
            sql = "SELECT count(*) FROM pg_locks WHERE locktype = 'advisory' AND pid = pg_backend_pid()"
            expect(connection.select_value(sql)).to eq(1)
          end
          original.call(**args)
        end
        status = { "id" => "wamid.1", "status" => "failed", "errors" => [{ "code" => 470, "title" => "Re-engagement" }] }

        2.times { api.process_event({ "statuses" => [status] }, nil) }

        expect(delivery_errors.map(&:action)).to eq(["errored: 470 Re-engagement"])
        expect(ApiChannelNotificatorJob).to have_received(:perform_later).once
      end
    end
  end

  describe "hooks" do
    include WebMock::API

    around(description: "create message with error") do |example|
      WebMock.enable!
      stub_request(:post, "https://waba-sandbox.360dialog.io/v1/messages")
        .to_return(status: 201, body: { messages: [{ id: "1" }] }.to_json)
      example.run
    ensure
      WebMock.reset!
      WebMock.disable!
    end

    before do
      AppPackagesCatalog.update_all
    end
    before :each do
      ActiveJob::Base.queue_adapter = :test
      ActiveJob::Base.queue_adapter.perform_enqueued_at_jobs = false

      allow_any_instance_of(AppPackageIntegration).to receive(:handle_registration)
        .and_return({})

      @pkg = app.app_package_integrations.create(
        api_secret: "aaa",
        api_key: "aaa",
        user_id: owner_phone,
        app_package: app_package,
        sandbox: true
      )

      allow_any_instance_of(MessageApis::Dialog360::Api).to receive(
        :direct_upload
      ).and_return({ url: "/direct-upload-mock" })
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
      expect(app.conversations.last.main_participant.name).to eql("Miguel Michelson")
      expect(app.conversations.last.messages.last.conversation_part_channel_sources).to be_any
    end

    it "receive conversation media" do
      allow_any_instance_of(
        MessageApis::Dialog360::Api
      ).to receive(:handle_direct_upload).and_return({ url: "/direct-upload-mock" })
      get(:process_event,
          params: data_for_media(
            id: @pkg.id,
            sender: owner_phone,
            message_id: "1234"
          ))
      perform_enqueued_jobs
      expect(response.status).to be == 200
      expect(app.conversations.count).to be == 1
      expect(app.conversations.last.messages).to be_any

      message = app.conversations.last.messages.last
      expect(message.conversation_part_channel_sources).to be_any
      expect(message.messageable.serialized_content).to include("/direct-upload-mock")
    end

    it "receive conversation video" do
      allow_any_instance_of(
        MessageApis::Dialog360::Api
      ).to receive(:handle_direct_upload).and_return({ url: "/direct-upload-mock" })
      get(:process_event,
          params: data_for_video(
            id: @pkg.id,
            sender: owner_phone,
            message_id: "1234"
          ))
      perform_enqueued_jobs
      expect(response.status).to be == 200
      expect(app.conversations.count).to be == 1
      expect(app.conversations.last.messages).to be_any

      message = app.conversations.last.messages.last
      expect(message.conversation_part_channel_sources).to be_any
      expect(message.messageable.serialized_content).to include("/direct-upload-mock")
    end

    it "receive conversation audio" do
      allow_any_instance_of(
        MessageApis::Dialog360::Api
      ).to receive(:handle_direct_upload).and_return({ url: "/direct-upload-mock" })
      get(:process_event,
          params: data_for_audio(
            id: @pkg.id,
            sender: owner_phone,
            message_id: "1234"
          ))
      perform_enqueued_jobs
      expect(response.status).to be == 200
      expect(app.conversations.count).to be == 1
      expect(app.conversations.last.messages).to be_any

      message = app.conversations.last.messages.last
      expect(message.conversation_part_channel_sources).to be_any
      expect(message.messageable.serialized_content).to include("/direct-upload-mock")
    end

    it "receive conversation sticker" do
      allow_any_instance_of(
        MessageApis::Dialog360::Api
      ).to receive(:handle_direct_upload).and_return({ url: "/direct-upload-mock" })
      get(:process_event,
          params: data_for_sticker(
            id: @pkg.id,
            sender: owner_phone,
            message_id: "1234"
          ))
      perform_enqueued_jobs
      expect(response.status).to be == 200
      expect(app.conversations.count).to be == 1
      expect(app.conversations.last.messages).to be_any

      message = app.conversations.last.messages.last
      expect(message.conversation_part_channel_sources).to be_any
      expect(message.messageable.serialized_content).to include("/direct-upload-mock")
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

    it "acknowledges status callbacks for an unknown attachment ID" do
      params = data_for_errors(id: @pkg.encoded_id, sender: user_phone, message_id: "wamid.untracked")
      params[:statuses] << { id: "wamid.untracked", status: "read" }

      perform_enqueued_jobs { post :process_event, params: params }

      expect(response).to have_http_status(:ok)
      expect(app.conversations).to be_empty
    end

    it "create message with error" do
      get(:process_event, params: data_for(
        id: @pkg.id,
        sender: user_phone,
        message_data: {
          "text" => "one\ntwo\ntree\n✌️"
        }
      ))
      perform_enqueued_jobs

      message = app.conversations.last.messages.last
      message.conversation_part_channel_sources.create(
        message_source_id: 1,
        provider: "Dialog360"
      )

      get(:process_event, params: data_for_errors(
        id: @pkg.encoded_id,
        message_id: 1,
        sender: user_phone
      ))

      allow_any_instance_of(
        MessageApis::Dialog360::Api
      ).to receive(:get_message_id).and_return(1)

      perform_enqueued_jobs

      last_message = app.conversations.last.messages.last
      expect(
        last_message.message
      ).to be_a(ConversationPartEvent)

      expect(
        last_message.conversation_part_channel_sources.first.message_source_id
      ).to include("bypass-internal")
    end
  end
end
