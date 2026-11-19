require "rails_helper"
include ActiveJob::TestHelper

RSpec.describe Api::V1::Hooks::ProviderController, type: :controller do
  let(:owner_phone) do
    "+1111"
  end

  let(:user_phone) do
    "+2222"
  end

  def contact
    { contact: {
      id: "75ef52b66cf24ebcbac8727cd4316ea8",
      href: "",
      msisdn: 56_992_302_305,
      displayName: "Miguel Michelson",
      firstName: "",
      lastName: "",
      customDetails: {},
      attributes: {},
      createdDatetime: "2021-02-02T20:37:30Z",
      updatedDatetime: "2021-02-02T20:37:30Z"
    } }
  end

  def conversation
    {
      conversation: {
        id: "7b2223447c3441e7961aab583ebe8d14",
        contactId: "75ef52b66cf24ebcbac8727cd4316ea8",
        status: "active",
        createdDatetime: "2021-02-02T20:37:30Z",
        updatedDatetime: "2021-02-08T13:18:43Z",
        lastReceivedDatetime: "2021-02-09T01:17:57.518405608Z",
        lastUsedChannelId: "f457361cf59348129ca387a52d4d7fe2",
        messages: {
          totalCount: 0,
          href: "https://whatsapp-sandbox.messagebird.com//v1/conversations/7b2223447c3441e7961aab583ebe8d14/messages"
        }
      }
    }
  end

  def data_for(id:, sender:, recipient:, message_id: nil, message_data: { "text" => "pokk" })
    {
      message: {
        id: message_id,
        conversationId: "7b2223447c3441e7961aab583ebe8d14",
        platform: "whatsapp",
        to: recipient,
        from: sender,
        channelId: "f457361cf59348129ca387a52d4d7fe2",
        type: "text",
        content: message_data,
        direction: "received",
        status: "received",
        createdDatetime: "2021-02-09T01:17:57Z",
        updatedDatetime: "2021-02-09T01:17:57.527914771Z"
      },
      type: "message.created",
      "controller" => "api/v1/hooks/provider",
      "action" => "process_event",
      "provider" => "message_bird",
      "app_key" => app.key,
      "id" => @pkg.encoded_id
    }.merge(contact).merge(conversation)
  end

  def data_for_media(id:, sender:, recipient:, message_id: nil, message_data: {})
    {
      message: {
        id: message_id,
        conversationId: "7b2223447c3441e7961aab583ebe8d14",
        platform: "whatsapp",
        to: recipient,
        from: sender,
        channelId: "f457361cf59348129ca387a52d4d7fe2",
        type: "image",
        content: {
          image: {
            url: "https://media.messagebird.com/v1/media/ab397184-a03a-42de-a2c7-69abc4a0ceaa",
            caption: "jij"
          }
        },
        direction: "received",
        status: "received",
        createdDatetime: "2021-02-09T01:22:59Z",
        updatedDatetime: "2021-02-09T01:23:01.353236248Z"
      },
      type: "message.created",
      "controller" => "api/v1/hooks/provider",
      "action" => "process_event",
      "provider" => "message_bird",
      "app_key" => app.key,
      "id" => @pkg.encoded_id
    }.merge(contact).merge(conversation)
  end

  def data_for_audio(id:, sender:, recipient:, message_id: nil, message_data: {})
    {
      message: {
        id: message_id,
        conversationId: "7b2223447c3441e7961aab583ebe8d14",
        platform: "whatsapp",
        to: recipient,
        from: sender,
        channelId: "f457361cf59348129ca387a52d4d7fe2",
        type: "audio",
        content: {
          audio: {
            url: "https://media.messagebird.com/v1/media/fa1ca4d6-5aa6-4379-a6ef-8d6ecbeb2617"
          }
        },
        direction: "received",
        status: "received",
        createdDatetime: "2021-02-09T01:22:59Z",
        updatedDatetime: "2021-02-09T01:23:01.353236248Z"
      },
      type: "message.created",
      "controller" => "api/v1/hooks/provider",
      "action" => "process_event",
      "provider" => "message_bird",
      "app_key" => app.key,
      "id" => @pkg.encoded_id
    }.merge(contact).merge(conversation)
  end

  def data_for_video(id:, sender:, recipient:, message_id: nil, message_data: {})
    {
      message: {
        id: message_id,
        conversationId: "7b2223447c3441e7961aab583ebe8d14",
        platform: "whatsapp",
        to: recipient,
        from: sender,
        channelId: "f457361cf59348129ca387a52d4d7fe2",
        type: "video",
        content: {
          video: {
            url: "https://media.messagebird.com/v1/media/2566f6eb-aa00-47fd-9608-604e08bb537d",
            caption: "hello"
          }
        },
        direction: "received",
        status: "received",
        createdDatetime: "2021-02-09T01:17:57Z",
        updatedDatetime: "2021-02-09T01:17:57.527914771Z"
      },
      type: "message.created",
      "controller" => "api/v1/hooks/provider",
      "action" => "process_event",
      "provider" => "message_bird",
      "app_key" => app.key,
      "id" => @pkg.encoded_id
    }.merge(contact).merge(conversation)
  end

  def data_for_read(id:, sender:, recipient:, message_id: nil, message_data: {})
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
      "provider" => "message_bird",
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
    1
    AppPackage.find_by(name: "MessageBird")
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
        api_secret: "aaa",
        api_key: "aaa",
        user_id: owner_phone,
        app_package: app_package,
        sandbox: true
      )

      allow_any_instance_of(MessageApis::MessageBird::Api).to receive(
        :direct_upload
      ).and_return({ url: "/direct-upload-mock" })
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
      expect(app.conversations.last.main_participant.name).to eql("Miguel Michelson")
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
      expect(message.messageable.serialized_content).to include("/direct-upload-mock")
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
      expect(message.messageable.serialized_content).to include("/direct-upload-mock")
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
      expect(message.messageable.serialized_content).to include("/direct-upload-mock")
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

    it "reply from agent on message_bird" do
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

  describe "MessageBird outgoing messages" do
    include WebMock::API

    around do |example|
      WebMock.enable!
      example.run
    ensure
      WebMock.reset!
      WebMock.disable!
    end

    let(:api) { MessageApis::MessageBird::Api.new(config: { "sandbox" => true, "user_id" => owner_phone }) }
    let(:endpoint) { "https://whatsapp-sandbox.messagebird.com/v1/send" }
    let(:recipient) { app.add_user(email: "recipient@example.com") }
    let(:thread) { app.conversations.create!(main_participant: recipient) }

    before do
      recipient.external_profiles.create!(provider: "message_bird", profile_id: user_phone)
    end

    def deliver(content)
      part = thread.messages.build(authorable: agent_role.agent, messageable: ConversationPartContent.new(content))
      api.send_message(thread, part)
    end

    def expect_delivery(text)
      stub = stub_request(:post, endpoint).with do |request|
        JSON.parse(request.body).dig("content", "text") == text
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
        JSON.parse(request.body).dig("content", "image", "url") == "https://chat.example.com/uploads/my%20photo.png"
      end.to_return(status: 200, body: "{}")
      image = { type: "ImageBlock", attrs: { url: "/uploads/my photo.png" } }
      deliver(serialized_content: { type: "doc", content: [image] }.to_json)
      assert_requested(stub)
    end

    it "sends attachments in document order and returns the first response" do
      contents = []
      stub_request(:post, endpoint).to_return do |request|
        contents << JSON.parse(request.body).slice("type", "content")
        { status: 200, body: { messages: [{ id: "mb-#{contents.size}" }] }.to_json }
      end
      blocks = [
        { type: "text", text: "See both files" },
        { type: "VideoBlock", attrs: { url: "https://cdn.example.com/clip.mp4" } },
        { type: "FileBlock", attrs: { url: "https://cdn.example.com/guide.pdf" } }
      ]

      response = deliver(serialized_content: { blocks: blocks }.to_json)

      expect(contents).to eq([
                               { "type" => "video", "content" => { "video" => { "url" => "https://cdn.example.com/clip.mp4", "caption" => "See both files" } } },
                               { "type" => "file", "content" => { "file" => { "url" => "https://cdn.example.com/guide.pdf" } } }
                             ])
      expect(api.get_message_id(JSON.parse(response.body))).to eq("mb-1")
    end

    it "records a partial failure for a rejected image" do
      stub_request(:post, endpoint).to_return(
        { status: 201, body: { id: "mb-1" }.to_json },
        { status: 422, body: { errors: [{ code: 21, description: "Unsupported image" }] }.to_json },
        { status: 201, body: { id: "mb-3" }.to_json }
      )
      images = %w[first second third].map { |name| { type: "ImageBlock", attrs: { url: "https://cdn.example.com/#{name}.png" } } }
      part = thread.add_message(from: agent_role.agent, message: { serialized_content: { content: images }.to_json })

      api.notify_message(conversation: thread, part: part, channel: user_phone)

      events = thread.messages.where(messageable_type: "ConversationPartEvent").map(&:messageable)
      failures = events.select { |event| event.action.start_with?("errored:") }
      expect(failures.map(&:data)).to eq([{ "status" => 422, "code" => 21, "message" => "Unsupported image" }])
      expect(part.conversation_part_channel_sources.pluck(:message_source_id)).to contain_exactly("mb-1", "mb-3")
    end

    it "ignores read webhooks with missing or blank provider ids" do
      part = thread.add_message(from: agent_role.agent, message: { html_content: "Expected unread" })
      part.conversation_part_channel_sources.create!(provider: "message_bird", delivery_index: 0)
      part.conversation_part_channel_sources.create!(provider: "message_bird", message_source_id: "", delivery_index: 1)
      statuses = [{ "status" => "read" }, { "status" => "read", "id" => "" }]

      api.process_event({ "statuses" => statuses }, nil)

      expect(part.reload.read_at).to be_nil
    end

    it "keeps the caption after a failed attachment and returns the first success" do
      captions = []
      stub_request(:post, endpoint).to_return do |request|
        captions << JSON.parse(request.body).dig("content", "image", "caption")
        { status: captions.size == 1 ? 422 : 201, body: { id: "mb-#{captions.size}" }.to_json }
      end
      blocks = [{ type: "text", text: "Show these images" }] + %w[first second third].map do |name|
        { type: "ImageBlock", attrs: { url: "https://cdn.example.com/#{name}.png" } }
      end

      response = deliver(serialized_content: { type: "doc", content: blocks }.to_json)

      expect(captions).to eq(["Show these images", "Show these images", nil])
      expect(api.get_message_id(JSON.parse(response.body))).to eq("mb-2")
    end

    it "returns the last response when every attachment and the fallback text fail" do
      types = []
      stub_request(:post, endpoint).to_return do |request|
        types << JSON.parse(request.body)["type"]
        { status: 400, body: { error: "rejected-#{types.size}" }.to_json }
      end
      blocks = [
        { type: "text", text: "Keep this text" },
        { type: "ImageBlock", attrs: { url: "https://cdn.example.com/image.png" } },
        { type: "FileBlock", attrs: { url: "https://cdn.example.com/guide.pdf" } }
      ]

      response = deliver(serialized_content: { type: "doc", content: blocks }.to_json)

      expect(types).to eq(%w[image file text])
      expect(JSON.parse(response.body)).to eq("error" => "rejected-3")
    end

    it "extracts the top-level id returned by /v1/send" do
      response_stub = stub_request(:post, endpoint).to_return(status: 201, body: { id: "mb-1" }.to_json)
      text = { type: "text", text: "Hello" }

      response = deliver(serialized_content: { type: "doc", content: [text] }.to_json)

      assert_requested(response_stub, times: 1)
      expect(api.get_message_id(JSON.parse(response.body))).to eq("mb-1")
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
