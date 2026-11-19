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

      allow_any_instance_of(AppPackageIntegration).to receive(:handle_registration)
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

    def document(*blocks)
      { type: "doc", content: blocks }.to_json
    end

    def attachment(url, type: "ImageBlock")
      { type: type, attrs: { url: url } }
    end

    def paragraph(text)
      { type: "paragraph", content: [{ type: "text", text: text }] }
    end

    def outgoing_part(content)
      thread.messages.create!(authorable: agent_role.agent,
                              messageable: ConversationPartContent.new(serialized_content: content))
    end

    def record_requests(*replies)
      bodies = []
      replies = [accepted("sent")] if replies.empty?
      stub_request(:post, endpoint).to_return do |request|
        bodies << JSON.parse(request.body)
        replies.size > 1 ? replies.shift : replies.first
      end
      bodies
    end

    def accepted(id)
      { status: 200, body: { data: { id: id } }.to_json }
    end

    def rejected
      errors = [{ code: "40305", title: "Invalid sender", source: { pointer: "/private-provider-field" } }]
      { status: 422, body: { errors: errors }.to_json }
    end

    def outbound_ids(part)
      part.conversation_part_channel_sources.where(provider: "TelnyxSms").pluck(:delivery_index, :message_source_id)
    end

    def delivery_errors
      thread.messages.reload.map(&:messageable).grep(ConversationPartEvent).select do |event|
        event.action.start_with?("errored:")
      end
    end

    it "sends each supported extension in its own media_urls and captions the first request" do
      urls = %w[jpg JPEG png gif mp4 3gp txt vcf vcard].map { |ext| "https://files.example.com/a.#{ext}?id=1" }
      bodies = record_requests
      deliver(serialized_content: document(paragraph("caption"), *urls.map { |url| attachment(url) }))

      expect(bodies.pluck("media_urls")).to eq(urls.map { |url| [url] })
      expect(bodies.pluck("text")).to eq(["caption"] + ([nil] * (urls.size - 1)))
      bodies.drop(1).each { |body| expect(body).not_to have_key("text") }
      expect(bodies.pluck("to").uniq).to eq(["+123"])
    end

    it "sends a media-only attachment using media_urls and no text field" do
      url = "https://files.example.com/clip.MP4"
      bodies = record_requests
      deliver(serialized_content: document(attachment(url, type: "VideoBlock")))

      expect(bodies.pluck("media_urls")).to eq([[url]])
      expect(bodies.first).not_to have_key("text")
    end

    it "appends an unsupported PDF as a link alongside supported media and as a standalone SMS" do
      pdf = "/rails/active_storage/blobs/redirect/abc/report.pdf"
      link = MessageApis::BlockManager.absolute_url(pdf)
      photo = "https://files.example.com/photo.png"
      bodies = record_requests
      pdf_block = attachment(pdf, type: "FileBlock")
      deliver(serialized_content: document(paragraph("read this"), attachment(photo), pdf_block))
      deliver(serialized_content: document(pdf_block))

      expect(bodies.pluck("text")).to eq(["read this\n#{link}", link])
      expect(bodies.first["media_urls"]).to eq([photo])
      expect(bodies.last).not_to have_key("media_urls")
    end

    it "keeps text-only SMS without media_urls (base-green)" do
      bodies = record_requests
      deliver(serialized_content: document(paragraph("SMS")))

      expect(bodies.size).to eq(1)
      expect(bodies.first).not_to have_key("media_urls")
    end

    it "stores each media message id with its delivery index" do
      record_requests(accepted("image-id"), accepted("video-id"))
      part = outgoing_part(document(attachment("https://files.example.com/photo.png"),
                                    attachment("https://files.example.com/clip.mp4", type: "VideoBlock")))

      api.notify_message(conversation: thread, part: part, channel: nil)

      expect(outbound_ids(part)).to contain_exactly([0, "image-id"], [1, "video-id"])
    end

    it "stores the message id of a text-only SMS" do
      record_requests(accepted("text-id"))
      part = outgoing_part(document(paragraph("SMS")))

      api.notify_message(conversation: thread, part: part, channel: nil)

      expect(outbound_ids(part)).to eq([[nil, "text-id"]])
    end

    it "stores the message id of a link-only SMS and avoids resending it" do
      bodies = record_requests(accepted("link-id"))
      part = outgoing_part(document(attachment("https://files.example.com/report.pdf", type: "FileBlock")))

      2.times { api.notify_message(conversation: thread, part: part, channel: nil) }

      expect(outbound_ids(part)).to eq([[0, "link-id"]])
      expect(bodies.pluck("text")).to eq(["https://files.example.com/report.pdf"])
    end

    it "sends only the remaining attachment without the original caption on retry" do
      bodies = record_requests(accepted("second-id"))
      first = "https://files.example.com/1.png"
      second = "https://files.example.com/2.png"
      part = outgoing_part(document(paragraph("caption"), attachment(first), attachment(second)))
      part.conversation_part_channel_sources.create!(provider: "TelnyxSms", delivery_index: 0,
                                                     message_source_id: "first-id")

      api.notify_message(conversation: thread, part: part, channel: nil)

      expect(bodies.pluck("media_urls")).to eq([[second]])
      expect(bodies.first).not_to have_key("text")
      expect(outbound_ids(part)).to contain_exactly([0, "first-id"], [1, "second-id"])
    end

    it "returns nil and records an errored event with only the safe provider fields" do
      record_requests(rejected)

      expect(deliver(serialized_content: document(paragraph("fail")))).to be_nil
      expect(delivery_errors.map(&:data)).to eq([{ "status" => 422, "code" => "40305", "message" => "Invalid sender" }])
    end

    it "stores the successful id and records the later error for a partly sent message" do
      record_requests(accepted("first-id"), rejected)
      part = outgoing_part(document(attachment("https://files.example.com/1.png"), attachment("https://files.example.com/2.png")))

      api.notify_message(conversation: thread, part: part, channel: nil)

      expect(outbound_ids(part)).to eq([[0, "first-id"]])
      expect(delivery_errors.map(&:data)).to eq([{ "status" => 422, "code" => "40305", "message" => "Invalid sender" }])
    end

    it "samples one sender from the pool for all three requests of one MMS message" do
      pool = %w[+15550001111 +15550002222]
      allow(api).to receive(:phones_data).and_return({ "1" => pool })
      allow(pool).to receive(:sample).and_return(*pool)
      bodies = record_requests
      attachments = (1..3).map { |index| attachment("https://files.example.com/#{index}.png") }

      deliver(serialized_content: document(paragraph("caption"), *attachments))

      expect(bodies.pluck("from")).to eq([pool.first] * 3)
      expect(pool).to have_received(:sample).once
    end
  end

  describe "TelnyxSms MMS and delivery webhooks" do
    include WebMock::API

    around do |example|
      WebMock.enable!
      example.run
    ensure
      WebMock.reset!
      WebMock.disable!
    end

    let(:package) { double(app: app, app_id: app.id) }
    let(:api) { MessageApis::TelnyxSms::Api.new(config: { api_key: "test-key", package: package }) }
    let(:png) { "\x89PNG\r\n\x1A\n#{'0' * 64}".b }

    before do
      allow(MessageApis::SafeDownload).to receive(:resolve).and_return(["93.184.216.34"])
    end

    def webhook(type, payload)
      params = { data: { event_type: type, payload: payload } }.with_indifferent_access
      api.process_event(params, package)
    end

    def receive_mms(*media, text: nil)
      payload = { id: "received-id", from: { phone_number: "+15557770000" }, text: text, media: media }
      webhook("message.received", payload)
    end

    def received_content
      app.conversations.last.messages.last.messageable
    end

    def received_blocks
      MessageApis::BlockManager.get_blocks(received_content.serialized_content)
    end

    def image(url)
      { url: url, content_type: "image/png" }
    end

    def serve(url, body: png, type: "image/png")
      stub_request(:get, url).to_return(body: body, headers: { "Content-Type" => type })
    end

    it "persists a media-only inbound MMS image and file in Active Storage and deduplicates the webhook" do
      photo = "https://media.telnyx.com/photo.png"
      file = "https://media.telnyx.com/report.pdf?signature=temporary"
      downloads = [serve(photo), serve(file, body: "%PDF-1.4\n%%EOF\n", type: "application/pdf")]

      expect do
        2.times { receive_mms(image(photo), { url: file }) }
      end.to change(ActiveStorage::Blob, :count).by(2)

      downloads.each { |download| assert_requested(download, times: 1) }
      expect(received_content.html_content).to eq("")
      expect(received_blocks.pluck("type")).to eq(%w[ImageBlock FileBlock])
      urls = received_blocks.map { |block| block.dig("attrs", "url") }
      expect(urls).to all(start_with("/rails/active_storage/"))
      expect(urls.map { |url| File.basename(url) }).to eq(%w[received-id-0.png received-id-1.pdf])
    end

    it "sends the API key to the apex, subdomain and mixed-case HTTPS media hosts" do
      urls = %w[https://telnyx.com/a.png https://media.telnyx.com/b.png https://Mms.Media.Telnyx.COM/c.png]
      downloads = urls.map do |url|
        stub_request(:get, url.downcase)
          .with(headers: { "Authorization" => "Bearer test-key" })
          .to_return(body: png, headers: { "Content-Type" => "image/png" })
      end

      receive_mms(*urls.map { |url| image(url) }, text: "first\nsecond")

      downloads.each { |download| assert_requested(download, times: 1) }
      expect(received_blocks.pluck("type")).to eq(%w[text text ImageBlock ImageBlock ImageBlock])
    end

    it "rejects plain http to a Telnyx host (base-green)" do
      url = "http://media.telnyx.com/photo.png"
      download = serve(url)
      receive_mms(image(url), text: "keep this")

      assert_not_requested(download)
      expect(received_content.html_content).to eq("keep this")
    end

    it "rejects lookalike Telnyx hosts and URLs with userinfo (base-green)" do
      urls = %w[https://eviltelnyx.com/a https://telnyx.com.evil.com/a https://telnyx.co/a https://user@media.telnyx.com/a]
      downloads = urls.map { |url| serve(url) }
      receive_mms(*urls.map { |url| image(url) }, text: "keep this")

      downloads.each { |download| assert_not_requested(download) }
      expect(received_blocks.pluck("type")).not_to include("ImageBlock")
    end

    it "logs a rejected foreign host without exposing its URL and keeps an unavailable attachment block" do
      url = "https://files.example.com/private.png?token=temporary"
      download = serve(url)
      allow(Rails.logger).to receive(:warn).and_call_original

      receive_mms(image(url), text: "keep this")

      assert_not_requested(download)
      expect(Rails.logger).to have_received(:warn).with(a_string_matching(/Telnyx/i))
      expect(Rails.logger).not_to have_received(:warn).with(a_string_including(url))
      expect(received_blocks.pluck("text")).to eq(["keep this", "[attachment unavailable: image/png]"])
    end

    it "drops the API key on a redirect to the same Telnyx host" do
      url = "https://media.telnyx.com/original.png"
      location = "https://media.telnyx.com/final.png"
      first = stub_request(:get, url)
              .with(headers: { "Authorization" => "Bearer test-key" })
              .to_return(status: 302, headers: { "Location" => location })
      redirected = serve(location).with { |request| !request.headers.key?("Authorization") }

      receive_mms(image(url))

      assert_requested(first, times: 1)
      assert_requested(redirected, times: 1)
      expect(received_blocks.pluck("type")).to eq(["ImageBlock"])
    end

    shared_examples "a rejected Telnyx media redirect" do |target|
      it "rejects a Telnyx media redirect to #{target} before making a request" do
        url = "https://media.telnyx.com/original.png"
        first = stub_request(:get, url).to_return(status: 302, headers: { "Location" => target })
        redirected = serve(target)

        receive_mms(image(url), text: "keep this")

        assert_requested(first, times: 1)
        assert_not_requested(redirected)
        expect(received_blocks.pluck("text")).to eq(["keep this", "[attachment unavailable: image/png]"])
      end
    end

    include_examples "a rejected Telnyx media redirect", "https://files.example.com/final.png"
    include_examples "a rejected Telnyx media redirect", "http://other.telnyx.com/final.png"

    it "follows a redirect to another HTTPS Telnyx subdomain without the API key" do
      url = "https://media.telnyx.com/original.png"
      target = "https://other.telnyx.com/final.png"
      first = stub_request(:get, url)
              .with(headers: { "Authorization" => "Bearer test-key" })
              .to_return(status: 302, headers: { "Location" => target })
      redirected = serve(target).with { |request| !request.headers.key?("Authorization") }

      receive_mms(image(url))

      assert_requested(first, times: 1)
      assert_requested(redirected, times: 1)
      expect(received_blocks.pluck("type")).to eq(["ImageBlock"])
    end

    it "keeps the text and remaining inbound MMS attachments if storage raises an error" do
      first = "https://media.telnyx.com/first.png"
      second = "https://media.telnyx.com/second.png"
      [first, second].each { |url| serve(url) }
      allow(api).to receive(:direct_upload).and_wrap_original do |upload, **options|
        raise IOError, "private storage error detail" if options[:filename].end_with?("-0.png")

        upload.call(**options)
      end
      allow(Rails.logger).to receive(:warn).and_call_original

      expect do
        receive_mms(image(first), image(second), text: "keep this")
      end.to change(ActiveStorage::Blob, :count).by(1)

      expect(received_blocks.pluck("type")).to eq(%w[text text ImageBlock])
      expect(received_blocks.first(2).pluck("text")).to eq(["keep this", "[attachment unavailable: image/png]"])
      expect(ActiveStorage::Blob.last.filename.to_s).to eq("received-id-1.png")
      expect(Rails.logger).to have_received(:warn).with(a_string_including("IOError"))
      expect(Rails.logger).not_to have_received(:warn).with(a_string_including("private storage error detail"))
    end

    it "stores an inbound MMS vCard with the .vcf extension" do
      url = "https://media.telnyx.com/contact"
      download = serve(url, body: "BEGIN:VCARD\nEND:VCARD\n", type: "text/vcard")

      expect { receive_mms({ url: url, content_type: "text/vcard" }) }.to change(ActiveStorage::Blob, :count).by(1)

      assert_requested(download, times: 1)
      expect(ActiveStorage::Blob.last.filename.to_s).to eq("received-id-0.vcf")
      expect(received_blocks.first.dig("attrs", "url")).to end_with("/received-id-0.vcf")
    end

    it "rejects media at a private address (base-green)" do
      url = "https://media.telnyx.com/photo.png"
      allow(MessageApis::SafeDownload).to receive(:resolve).with("media.telnyx.com").and_return(["10.0.0.5"])
      download = serve(url)

      receive_mms(image(url), text: "keep this")

      assert_not_requested(download)
      expect(received_blocks.pluck("type")).not_to include("ImageBlock")
    end

    it "rejects private Telnyx media even on the application's own host (base-green)" do
      url = "https://media.telnyx.com/photo.png"
      allow(MessageApis::SafeDownload).to receive(:resolve).with("media.telnyx.com").and_return(["10.0.0.5"])
      allow(Chaskiq::Config).to receive(:get).and_call_original
      allow(Chaskiq::Config).to receive(:get).with("HOST").and_return("https://media.telnyx.com")
      download = serve(url)

      receive_mms(image(url), text: "keep this")

      assert_not_requested(download)
    end

    it "does not store oversized media over five MiB (base-green)" do
      url = "https://media.telnyx.com/clip.mp4"
      serve(url, body: "0" * ((5 * 1024 * 1024) + 1), type: "video/mp4")

      expect do
        receive_mms({ url: url, content_type: "video/mp4" }, text: "keep this")
      end.not_to change(ActiveStorage::Blob, :count)
      expect(received_blocks.pluck("type")).not_to include("FileBlock")
    end

    it "ignores a message without text or media" do
      expect { receive_mms }.not_to change(Conversation, :count)
    end

    def tracked_part(owner_app)
      recipient = owner_app.add_user(email: "status-recipient@example.com")
      conversation = owner_app.conversations.create!(main_participant: recipient)
      content = ConversationPartContent.new(html_content: "tracked message")
      part = conversation.messages.create!(authorable: recipient, messageable: content)
      part.conversation_part_channel_sources.create!(provider: "TelnyxSms", message_source_id: "tracked-id")
      part
    end

    def delivery_status(status, event: "message.finalized", errors: [])
      webhook(event, { id: "tracked-id", to: [{ status: status }], errors: errors })
    end

    def status_events(part)
      part.conversation.messages.reload.map(&:messageable).grep(ConversationPartEvent)
    end

    it "marks a part read after delivered while message.sent and delivery_unconfirmed leave it unread" do
      part = tracked_part(app)
      delivery_status("sent", event: "message.sent")
      expect(part.reload.read_at).to be_nil
      delivery_status("delivery_unconfirmed")
      expect(part.reload.read_at).to be_nil

      delivery_status("delivered")
      expect(part.reload.read_at).to be_present
    end

    it "records a failed delivery once on webhook replay with only sanitized fields" do
      part = tracked_part(app)
      error = { code: "40002", title: "Invalid destination https://files.example.com/private", source: { pointer: "/raw" } }

      2.times { delivery_status("delivery_failed", errors: [error]) }

      expect(part.reload.read_at).to be_nil
      event_data = { "status" => nil, "code" => "40002", "message" => "Invalid destination [url]" }
      expect(status_events(part).map(&:data)).to eq([event_data])
    end

    it "ignores delivered and failed callbacks for a part in another app" do
      part = tracked_part(FactoryBot.create(:app))

      delivery_status("delivered")
      delivery_status("delivery_failed", errors: [{ title: "Invalid destination" }])

      expect(part.reload.read_at).to be_nil
      expect(status_events(part)).to be_empty
    end
  end
end
