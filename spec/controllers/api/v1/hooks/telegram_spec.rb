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
      update_id: 779_649_024,
      message: {
        message_id: message_id,
        from: {
          id: sender,
          is_bot: false,
          first_name: "Miguel",
          last_name: "Michelson",
          language_code: "en"
        },
        chat: {
          id: sender,
          first_name: "Miguel",
          last_name: "Michelson",
          type: "private"
        },
        date: 1_631_603_019,
        text: message_data["text"] || "hey!"
      },

      "controller" => "api/v1/hooks/provider",
      "action" => "process_event",
      "provider" => "telegram",
      "app_key" => app.key,
      "id" => @pkg.encoded_id
    }
  end

  def data_for_media(id:, sender:, message_id: nil, message_data: {})
    {

      update_id: 779_649_030,
      message: {
        message_id: message_id,
        from: {
          id: sender,
          is_bot: false,
          first_name: "Miguel",
          last_name: "Michelson",
          language_code: "en"
        },
        chat: {
          id: sender,
          first_name: "Miguel",
          last_name: "Michelson",
          type: "private"
        },
        date: 1_631_633_532,
        animation: {
          file_name: "@KoksalGif - 3460.gif.mp4",
          mime_type: "video/mp4",
          duration: 6,
          width: 316,
          height: 320,
          thumb: {
            file_id: "AAMCAgADGQEAAxZhQMB8gOAAAVyuph7F3adGf9CKF2MAAtkGAALIYwhKcxVSFXYKQHUBAAdtAAMgBA",
            file_unique_id: "AQAD2QYAAshjCEpy",
            file_size: 14_509,
            width: 315,
            height: 320
          },
          file_id: "CgACAgIAAxkBAAMWYUDAfIDgAAFcrqYexd2nRn_QihdjAALZBgACyGMISnMVUhV2CkB1IAQ",
          file_unique_id: "AgAD2QYAAshjCEo",
          file_size: 90_400
        },
        document: {
          file_name: "@KoksalGif - 3460.gif.mp4",
          mime_type: "video/mp4",
          thumb: {
            file_id: "AAMCAgADGQEAAxZhQMB8gOAAAVyuph7F3adGf9CKF2MAAtkGAALIYwhKcxVSFXYKQHUBAAdtAAMgBA",
            file_unique_id: "AQAD2QYAAshjCEpy",
            file_size: 14_509,
            width: 315,
            height: 320
          },
          file_id: "CgACAgIAAxkBAAMWYUDAfIDgAAFcrqYexd2nRn_QihdjAALZBgACyGMISnMVUhV2CkB1IAQ",
          file_unique_id: "AgAD2QYAAshjCEo",
          file_size: 90_400
        }
      },

      "controller" => "api/v1/hooks/provider",
      "action" => "process_event",
      "provider" => "telegram",
      "app_key" => app.key,
      "id" => @pkg.encoded_id
    }
  end

  def data_for_audio(id:, sender:, message_id: nil, message_data: {})
    {
      update_id: 779_649_032,
      message: {
        message_id: message_id,
        from: {
          id: sender,
          is_bot: false,
          first_name: "Miguel",
          last_name: "Michelson",
          language_code: "en"
        },
        chat: {
          id: sender,
          first_name: "Miguel",
          last_name: "Michelson",
          type: "private"
        },
        date: 1_631_674_175,
        voice: {
          duration: 4,
          mime_type: "audio/ogg",
          file_id: "AwACAgEAAxkBAAMeYUFfPxq6g7RI__x1JODaKa0YDhwAAmABAAJTPBBGfwxFZti0lQkgBA",
          file_unique_id: "AgADYAEAAlM8EEY",
          file_size: 26_087
        }
      },
      "controller" => "api/v1/hooks/provider",
      "action" => "process_event",
      "provider" => "telegram",
      "app_key" => app.key,
      "id" => @pkg.encoded_id
    }
  end

  def data_for_video(id:, sender:, message_id: nil, message_data: {})
    {
      update_id: 779_649_035,
      message: {
        message_id: 33,
        from: {
          id: sender,
          is_bot: false,
          first_name: "Miguel",
          last_name: "Michelson",
          language_code: "en"
        },
        chat: {
          id: sender,
          first_name: "Miguel",
          last_name: "Michelson",
          type: "private"
        },
        date: 1_631_676_328,
        animation: {
          file_name: "E5eTEjNXMAUYXfJ.mp4",
          mime_type: "video/mp4",
          duration: 6,
          width: 336,
          height: 320,
          thumb: {
            file_id: "AAMCAQADGQEAAyFhQWeoUPChcGb14kZe2k-_GOCM0wACYgEAAlM8EEYyYeCv-Up6CQEAB20AAyAE",
            file_unique_id: "AQADYgEAAlM8EEZy",
            file_size: 12_675,
            width: 320,
            height: 305
          },
          file_id: "CgACAgEAAxkBAAMhYUFnqFDwoXBm9eJGXtpPvxjgjNMAAmIBAAJTPBBGMmHgr_lKegkgBA",
          file_unique_id: "AgADYgEAAlM8EEY",
          file_size: 86_980
        },
        document: {
          file_name: "E5eTEjNXMAUYXfJ.mp4",
          mime_type: "video/mp4",
          thumb: {
            file_id: "AAMCAQADGQEAAyFhQWeoUPChcGb14kZe2k-_GOCM0wACYgEAAlM8EEYyYeCv-Up6CQEAB20AAyAE",
            file_unique_id: "AQADYgEAAlM8EEZy",
            file_size: 12_675,
            width: 320,
            height: 305
          },
          file_id: "CgACAgEAAxkBAAMhYUFnqFDwoXBm9eJGXtpPvxjgjNMAAmIBAAJTPBBGMmHgr_lKegkgBA",
          file_unique_id: "AgADYgEAAlM8EEY",
          file_size: 86_980
        },
        caption: "hello"
      },
      "controller" => "api/v1/hooks/provider",
      "action" => "process_event",
      "provider" => "telegram",
      "app_key" => app.key,
      "id" => @pkg.encoded_id
    }
  end

  def data_for_image(id:, sender:, message_id: nil, message_data: {})
    {
      message: {
        message_id: 32,
        from: {
          id: sender,
          is_bot: false,
          first_name: "Miguel",
          last_name: "Michelson",
          language_code: "en"
        },
        chat: {
          id: sender,
          first_name: "Miguel",
          last_name: "Michelson",
          type: "private"
        },
        date: 1_631_675_712,
        photo: [
          {
            file_id: "AgACAgEAAxkBAAMgYUFlQDPVTLa3N0MMVSiYOlDDlwEAAl6qMRtTPBBGkP7Xqc4QJHsBAAMCAANzAAMgBA",
            file_unique_id: "AQADXqoxG1M8EEZ4",
            file_size: 1329,
            width: 67,
            height: 90
          },
          {
            file_id: "AgACAgEAAxkBAAMgYUFlQDPVTLa3N0MMVSiYOlDDlwEAAl6qMRtTPBBGkP7Xqc4QJHsBAAMCAANtAAMgBA",
            file_unique_id: "AQADXqoxG1M8EEZy",
            file_size: 20_068,
            width: 240,
            height: 320
          },
          {
            file_id: "AgACAgEAAxkBAAMgYUFlQDPVTLa3N0MMVSiYOlDDlwEAAl6qMRtTPBBGkP7Xqc4QJHsBAAMCAAN4AAMgBA",
            file_unique_id: "AQADXqoxG1M8EEZ9",
            file_size: 78_945,
            width: 600,
            height: 800
          },
          {
            file_id: "AgACAgEAAxkBAAMgYUFlQDPVTLa3N0MMVSiYOlDDlwEAAl6qMRtTPBBGkP7Xqc4QJHsBAAMCAAN5AAMgBA",
            file_unique_id: "AQADXqoxG1M8EEZ-",
            file_size: 88_510,
            width: 867,
            height: 1156
          }
        ],
        caption: "oliii"
      },
      "controller" => "api/v1/hooks/provider",
      "action" => "process_event",
      "provider" => "telegram",
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
      "provider" => "telegram",
      "app_key" => app.key,
      "id" => id
    }
  end

  def data_for_sticker(id:, sender:, message_id: nil, message_data: {})
    {
      update_id: 779_649_031,
      message: {
        message_id: message_id,
        from: {
          id: sender,
          is_bot: false,
          first_name: "Miguel",
          last_name: "Michelson",
          language_code: "en"
        },
        chat: {
          id: sender,
          first_name: "Miguel",
          last_name: "Michelson",
          type: "private"
        },
        date: 1_631_673_514,
        sticker: {
          width: 512,
          height: 512,
          emoji: "😂",
          set_name: "HotCherry",
          is_animated: true,
          thumb: {
            file_id: "AAMCAgADGQEAAx1hQVyqbuun9bpvoJvkyacBz9BogQACAQADwDZPExguczCrPy1RAQAHbQADIAQ",
            file_unique_id: "AQADAQADwDZPE3I",
            file_size: 2750,
            width: 128,
            height: 128
          },
          file_id: "CAACAgIAAxkBAAMdYUFcqm7rp_W6b6Cb5MmnAc_QaIEAAgEAA8A2TxMYLnMwqz8tUSAE",
          file_unique_id: "AgADAQADwDZPEw",
          file_size: 8244
        }
      },
      "controller" => "api/v1/hooks/provider",
      "action" => "process_event",
      "provider" => "telegram",
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
    AppPackage.find_by(name: "Telegram")
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
        access_token: "aaa",
        user_id: owner_phone,
        app_package: app_package,
        sandbox: true
      )

      allow_any_instance_of(MessageApis::Telegram::Api).to receive(
        :handle_direct_upload
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

    it "receive conversation sticker" do
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

    it "receive conversation audio" do
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

    it "receive conversation video" do
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

    it "receive conversation image" do
      get(:process_event,
          params: data_for_image(
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
  end

  describe "Telegram outgoing messages" do
    include WebMock::API

    around do |example|
      WebMock.enable!
      example.run
    ensure
      WebMock.reset!
      WebMock.disable!
    end

    let(:api) { MessageApis::Telegram::Api.new(config: { "access_token" => "test-bot" }) }
    let(:endpoint) { "https://api.telegram.org/bottest-bot/sendMessage" }
    let(:recipient) { app.add_user(email: "recipient@example.com") }
    let(:thread) { app.conversations.create!(main_participant: recipient) }

    before do
      thread.conversation_channels.create!(provider: "telegram", provider_channel_id: "123")
    end

    def deliver(content)
      part = thread.messages.build(authorable: agent_role.agent, messageable: ConversationPartContent.new(content))
      api.send_message(thread, part)
    end

    def expect_delivery(text)
      stub = stub_request(:post, endpoint).with do |request|
        JSON.parse(request.body)["text"] == text
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

    it "sends a newline between paragraph blocks" do
      stub = expect_delivery("order\n123")
      paragraphs = %w[order 123].map do |text|
        { type: "paragraph", content: [{ type: "text", text: text }] }
      end
      deliver(serialized_content: { type: "doc", content: paragraphs }.to_json)
      assert_requested(stub)
    end

    it "encodes a space in a relative photo URL" do
      allow(Chaskiq::Config).to receive(:get).and_call_original
      allow(Chaskiq::Config).to receive(:get).with("HOST").and_return("https://chat.example.com/")
      stub = stub_request(:post, "https://api.telegram.org/bottest-bot/sendPhoto").with do |request|
        JSON.parse(request.body)["photo"] == "https://chat.example.com/uploads/my%20photo.png"
      end.to_return(status: 200, body: "{}")
      image = { type: "ImageBlock", attrs: { url: "/uploads/my photo.png" } }
      deliver(serialized_content: { type: "doc", content: [image] }.to_json)
      assert_requested(stub)
    end

    it "sends attachments in document order and returns the first response" do
      calls = []
      stub_request(:post, %r{https://api.telegram.org/bottest-bot/send(?:Document|Audio)})
        .to_return do |request|
          calls << [request.uri.path.split("/").last, JSON.parse(request.body)]
          { status: 200, body: { result: { message_id: calls.size } }.to_json }
        end
      blocks = [
        { type: "FileBlock", attrs: { url: "https://cdn.example.com/guide.pdf" } },
        { type: "AudioRecorderBlock", attrs: { url: "https://cdn.example.com/clip.mp3" } }
      ]

      response = deliver(serialized_content: { type: "doc", content: blocks }.to_json)

      expect(calls).to eq([
                            ["sendDocument", { "document" => "https://cdn.example.com/guide.pdf", "chat_id" => "123" }],
                            ["sendAudio", { "audio" => "https://cdn.example.com/clip.mp3", "chat_id" => "123" }]
                          ])
      expect(api.get_message_id(JSON.parse(response.body))).to eq(1)
    end

    it "records a partial failure for a rejected photo" do
      stub_request(:post, "https://api.telegram.org/bottest-bot/sendPhoto").to_return(
        { status: 200, body: { result: { message_id: 101 } }.to_json },
        { status: 400, body: { error_code: 400, description: "Invalid photo" }.to_json },
        { status: 200, body: { result: { message_id: 103 } }.to_json }
      )
      photos = %w[first second third].map { |name| { type: "ImageBlock", attrs: { url: "https://cdn.example.com/#{name}.png" } } }
      part = thread.add_message(from: agent_role.agent, message: { serialized_content: { content: photos }.to_json })

      api.notify_message(conversation: thread, part: part, channel: "123")

      events = thread.messages.where(messageable_type: "ConversationPartEvent").map(&:messageable)
      expect(events.map(&:action).grep(/^errored:/)).to eq(["errored: Invalid photo"])
      expect(part.conversation_part_channel_sources.pluck(:message_source_id)).to contain_exactly("101", "103")
    end

    it "adds the caption only to the first attachment with a usable URL" do
      calls = []
      stub_request(:post, "https://api.telegram.org/bottest-bot/sendPhoto").to_return do |request|
        calls << JSON.parse(request.body)
        { status: 200, body: "{}" }
      end
      blocks = [
        { type: "ImageBlock", attrs: { url: "" } },
        { type: "text", text: "See both images" },
        { type: "ImageBlock", attrs: { url: "https://cdn.example.com/first.png" } },
        { type: "ImageBlock", attrs: { url: "https://cdn.example.com/second.png" } }
      ]

      deliver(serialized_content: { type: "doc", content: blocks }.to_json)

      expect(calls.map { |body| body["photo"] }).to eq(%w[https://cdn.example.com/first.png https://cdn.example.com/second.png])
      expect(calls.map { |body| body["caption"].to_s }).to eq(["See both images", ""])
    end

    it "keeps the caption after a failed attachment and returns the first success" do
      url = "https://api.telegram.org/bottest-bot/sendPhoto"
      captions = []
      stub_request(:post, url).to_return do |request|
        captions << JSON.parse(request.body)["caption"]
        { status: captions.size == 1 ? 400 : 200, body: { result: { message_id: captions.size } }.to_json }
      end
      blocks = [{ type: "text", text: "Show these images" }] + %w[first second third].map do |name|
        { type: "ImageBlock", attrs: { url: "https://cdn.example.com/#{name}.png" } }
      end

      response = deliver(serialized_content: { type: "doc", content: blocks }.to_json)

      expect(captions).to eq(["Show these images", "Show these images", nil])
      expect(api.get_message_id(JSON.parse(response.body))).to eq(2)
    end

    it "sends text on its own after every attachment is rejected" do
      images = stub_request(:post, "https://api.telegram.org/bottest-bot/sendPhoto").to_return(status: 400)
      text = stub_request(:post, endpoint).with do |request|
        JSON.parse(request.body) == { "chat_id" => "123", "text" => "Keep this text" }
      end.to_return(status: 200, body: { result: { message_id: 3 } }.to_json)
      blocks = [{ type: "text", text: "Keep this text" }] + %w[first second].map do |name|
        { type: "ImageBlock", attrs: { url: "https://cdn.example.com/#{name}.png" } }
      end

      response = deliver(serialized_content: { type: "doc", content: blocks }.to_json)

      assert_requested(images, times: 2)
      assert_requested(text, times: 1)
      expect(api.get_message_id(JSON.parse(response.body))).to eq(3)
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
