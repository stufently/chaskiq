require "rails_helper"
include ActiveJob::TestHelper

RSpec.describe Api::V1::Hooks::ProviderController, type: :controller do
  let(:owner_phone) do
    "1111"
  end

  let(:user_phone) do
    "2222"
  end

  def data_for(id:, sender:, recipient:, message_id: nil, message_data: {})
    {
      message_uuid: message_id,
      from: {	type: "whatsapp",	number: sender },
      to: { type: "whatsapp", number: recipient },
      message: {
        content: {
          type: "text",
          text: message_data.blank? ? "hola" : message_data["text"]
        }
      },
      timestamp: "2021-02-03T18:04:52.936Z",

      "controller" => "api/v1/hooks/provider",
      "action" => "process_event",
      "provider" => "vonage",
      "app_key" => app.key,
      "id" => @pkg.encoded_id
    }
  end

  def data_for_media(id:, sender:, recipient:, message_id: nil, message_data: {})
    {
      message_uuid: message_id,
      from: {	type: "whatsapp",	number: sender },
      to: { type: "whatsapp", number: recipient },
      message: {
        content: {
          type: "image",
          image: {
            url: "https://api.nexmo.com/v3/media/c7e601e8-708b-4fc3-b7cf-92f60c185cd4",
            caption: "hola"
          }
        }
      },
      timestamp: "2021-02-03T18:10:40.311Z",

      # "MediaContentType0"=>"image/jpeg",
      # "SmsMessageSid"=>message_id,
      # "NumMedia"=>"1",
      # "SmsSid"=>message_id,
      # "SmsStatus"=>"received",
      # "Body"=>"",
      # "To"=>"whatsapp:+1111",
      # "NumSegments"=>"1",
      # "MessageSid"=>message_id,
      # "AccountSid"=>"ACe290",
      # "From"=>"whatsapp:+2222",
      # "MediaUrl0"=>"https://api.twilio.com/2010-04-01/Accounts/AAAA/Messages/AAAAAAAAA/Media/MEf98b16d258dbb7380e44996a3337c54c",
      # "ApiVersion"=>"2010-04-01",
      "action" => "process_event",
      "provider" => "vonage",
      "controller" => "api/v1/hooks/provider",
      "app_key" => app.key,
      "id" => @pkg.encoded_id
    }
  end

  def data_for_audio(id:, sender:, recipient:, message_id: nil, message_data: {})
    {
      message_uuid: message_id,
      from: {	type: "whatsapp",	number: sender },
      to: { type: "whatsapp", number: recipient },
      message: {
        content: {
          type: "audio",
          audio: {
            url: "https://api.nexmo.com/v3/media/7a620c45-3d75-4b42-a29f-0379a3798169"
          }
        }
      },
      timestamp: "2021-02-03T18:10:40.311Z",
      "action" => "process_event",
      "provider" => "vonage",
      "controller" => "api/v1/hooks/provider",
      "app_key" => app.key,
      "id" => @pkg.encoded_id
    }
  end

  def data_for_video(id:, sender:, recipient:, message_id: nil, message_data: {})
    {
      message_uuid: message_id,
      from: {	type: "whatsapp",	number: sender },
      to: { type: "whatsapp", number: recipient },
      message: {
        content: {
          type: "video",
          video: {
            url: "https://api.nexmo.com/v3/media/ae78f99c-4dde-4dd7-81e0-81b71a6dba13",
            caption: "iojij"
          }
        }
      },
      timestamp: "2021-02-03T18:10:40.311Z",
      "action" => "process_event",
      "provider" => "vonage",
      "controller" => "api/v1/hooks/provider",
      "app_key" => app.key,
      "id" => @pkg.encoded_id
    }
  end

  def data_for_read(id:, sender:, recipient:, message_id: nil, message_data: {})
    {
      message_uuid: "1f882e4c-75d1-4625-aa0a-2e5f8e068de9",
      from: {
        type: "whatsapp",
        number: "14157386170"
      },
      to: {
        type: "whatsapp",
        number: "56992302305"
      },
      timestamp: "2021-02-04T03:05:17.616Z",
      status: "read"
    }
  end

  let!(:app) do
    FactoryBot.create(:app)
  end

  let!(:agent_role) do
    app.add_agent({ email: "test2@test.cl" })
  end

  let(:app_package) do
    AppPackage.find_by(name: "Vonage")
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
        api_secret: "aaa",
        api_key: "aaa",
        user_id: owner_phone,
        app_package: app_package,
        sandbox: true
      )
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
      expect(message.messageable.serialized_content).to include("https://api.nexmo.com/v3/media/")
    end

    it "receive conversation video" do
      get(:process_event,
          params: data_for_video(
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
      expect(message.messageable.serialized_content).to include("https://api.nexmo.com/v3/media/")
    end

    it "receive conversation audio" do
      get(:process_event,
          params: data_for_audio(
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

      expect(message.messageable.serialized_content).to include("https://api.nexmo.com/v3/media/")
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

    it "reply from agent on vonage" do
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
  end

  describe "Vonage outgoing messages" do
    include WebMock::API

    around do |example|
      WebMock.enable!
      example.run
    ensure
      WebMock.reset!
      WebMock.disable!
    end

    let(:api) { MessageApis::Vonage::Api.new(config: { "sandbox" => true, "user_id" => owner_phone }) }
    let(:endpoint) { "https://messages-sandbox.nexmo.com/v0.1/messages" }
    let(:recipient) { app.add_user(email: "recipient@example.com") }
    let(:thread) { app.conversations.create!(main_participant: recipient) }

    before do
      recipient.external_profiles.create!(provider: "vonage", profile_id: user_phone)
    end

    def deliver(content)
      part = thread.messages.build(authorable: agent_role.agent, messageable: ConversationPartContent.new(content))
      api.send_message(thread, part)
    end

    def expect_delivery(text)
      stub = stub_request(:post, endpoint).with do |request|
        JSON.parse(request.body).dig("message", "content", "text") == text
      end
      stub.to_return(status: 200, body: "{}")
    end

    it "sends the outgoing Dante paragraph to the provider" do
      stub = expect_delivery("foobar")
      doc = { type: "doc", content: [{ type: "paragraph", content: [{ type: "text", text: "foobar" }] }] }
      deliver(serialized_content: doc.to_json)
      assert_requested(stub)
    end

    it "sends text from the legacy blocks wrapper" do
      stub = expect_delivery("forwarded text")
      legacy = { blocks: [{ type: "text", text: "forwarded text" }], entityMap: {} }
      deliver(serialized_content: legacy.to_json)
      assert_requested(stub)
    end

    it "sends an absolute encoded URL for a relative media path with a space" do
      allow(Chaskiq::Config).to receive(:get).and_call_original
      allow(Chaskiq::Config).to receive(:get).with("HOST").and_return("https://chat.example.com/")
      stub = stub_request(:post, endpoint).with do |request|
        JSON.parse(request.body).dig("message", "content", "image", "url") == "https://chat.example.com/uploads/my%20photo.png"
      end.to_return(status: 200, body: "{}")
      image = { type: "ImageBlock", attrs: { url: "/uploads/my photo.png" } }
      deliver(serialized_content: { type: "doc", content: [image] }.to_json)
      assert_requested(stub)
    end

    it "sends attachments in document order and returns the first response" do
      contents = []
      stub_request(:post, endpoint).to_return do |request|
        contents << JSON.parse(request.body).dig("message", "content")
        { status: 200, body: { message_uuid: "uuid-#{contents.size}" }.to_json }
      end
      blocks = [
        { type: "text", text: "See both files" },
        { type: "ImageBlock", attrs: { url: "https://cdn.example.com/image.png" } },
        { type: "FileBlock", attrs: { url: "https://cdn.example.com/guide.pdf" } }
      ]

      response = deliver(serialized_content: { type: "doc", content: blocks }.to_json)

      expect(contents).to eq([
        { "type" => "image", "image" => { "url" => "https://cdn.example.com/image.png", "caption" => "See both files" } },
        { "type" => "file", "file" => { "url" => "https://cdn.example.com/guide.pdf" } }
      ])
      expect(api.get_message_id(JSON.parse(response.body))).to eq("uuid-1")
    end

    context "when notifying a saved message" do
      let(:urls) { %w[first second third fourth].map { |name| "https://cdn.example.com/#{name}.png" } }
      let(:part) do
        blocks = [{ type: "text", text: "Caption" }] + urls.map { |url| { type: "ImageBlock", attrs: { url: url } } }
        thread.add_message(from: agent_role.agent, message: { serialized_content: { content: blocks }.to_json })
      end

      def notify
        api.notify_message(conversation: thread, part: part, channel: user_phone)
      end

      def successful_response(number)
        { status: 202, body: { message_uuid: "uuid-#{number}" }.to_json }
      end

      def source_ids
        part.conversation_part_channel_sources.where(provider: "vonage").order(:id).pluck(:message_source_id)
      end

      it "records a partial failure for rejected media" do
        stub_request(:post, endpoint).to_return(
          successful_response(1), { status: 422, body: { title: "Invalid media" }.to_json },
          successful_response(3), successful_response(4)
        )

        notify

        failures = thread.messages.where(messageable_type: "ConversationPartEvent").map(&:messageable)
                         .select { |event| event.action.start_with?("errored:") }
        expect(failures.map(&:data)).to eq([{ "status" => 422, "code" => nil, "message" => "Invalid media" }])
      end

      it "marks a part as read through a later provider id" do
        stub_request(:post, endpoint).to_return(*(1..4).map { |number| successful_response(number) })

        notify
        api.process_event({ "status" => "read", "message_uuid" => "uuid-3" }, nil)

        expect(part.reload.read_at).to be_present
        expect(source_ids).to eq(%w[uuid-1 uuid-2 uuid-3 uuid-4])
      end

      it "persists each accepted id immediately before the next POST" do
        observed = []
        stub_request(:post, endpoint).to_return do
          observed << source_ids
          successful_response(observed.size)
        end

        notify

        expect(observed).to eq([[], ["uuid-1"], %w[uuid-1 uuid-2], %w[uuid-1 uuid-2 uuid-3]])
      end

      it "can resume the series after the third attachment times out" do
        sent_images = []
        stub_request(:post, endpoint).to_return do |request|
          sent_images << JSON.parse(request.body).dig("message", "content", "image")
          raise Faraday::TimeoutError if sent_images.size == 3

          successful_response(sent_images.size)
        end

        expect { notify }.to raise_error(Faraday::TimeoutError)
        notify

        expect(sent_images.drop(3)).to eq(urls.last(2).map { |url| { "url" => url } })
        expect(source_ids).to eq(%w[uuid-1 uuid-2 uuid-4 uuid-5])
      end

      it "makes no requests on retry after all media was sent (base-green)" do
        stub = stub_request(:post, endpoint).to_return(*(1..4).map { |number| successful_response(number) })

        2.times { notify }

        assert_requested(stub, times: 4)
      end
    end

    it "keeps the caption after a failed attachment and returns the first success" do
      captions = []
      stub_request(:post, endpoint).to_return do |request|
        captions << JSON.parse(request.body).dig("message", "content", "file", "caption")
        { status: captions.size == 1 ? 500 : 202, body: { message_uuid: "uuid-#{captions.size}" }.to_json }
      end
      blocks = [{ type: "text", text: "Read these files" }] + %w[first second third].map do |name|
        { type: "FileBlock", attrs: { url: "https://cdn.example.com/#{name}.pdf" } }
      end

      response = deliver(serialized_content: { type: "doc", content: blocks }.to_json)

      expect(captions).to eq(["Read these files", "Read these files", nil])
      expect(api.get_message_id(JSON.parse(response.body))).to eq("uuid-2")
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
