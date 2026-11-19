# frozen_string_literal: true

# Probe for fork-updates-m11: Telnyx MMS (send media, receive media through SafeDownload, status callbacks).
# Needs fork-updates-m9 merged (deliver_attachments on_success:/on_failure:, BasePackage#delivery_hooks).
# Run (P=docs/specs/fork-updates-m11-probes): bash $P/rspec_gate_m11.sh --only $P/m11_probe_spec.rb
# webmock for HTTP, SafeDownload.resolve stubbed: no network.
require "rails_helper"
require "webmock"

# Metrics/BlockLength: probe spec; spec/** is excluded the same way in .rubocop.yml.
# rubocop:disable-next Metrics/BlockLength
RSpec.describe Api::V1::Hooks::ProviderController, type: :controller do
  include ActiveJob::TestHelper
  include WebMock::API

  around do |example|
    WebMock.enable!
    example.run
  ensure
    WebMock.reset!
    WebMock.disable!
  end

  let(:png) { "\x89PNG\r\n\x1A\n#{'0' * 64}".b }
  let(:pdf) { "%PDF-1.4\n%%EOF\n".b }
  let(:endpoint) { "https://api.telnyx.com/v2/messages" }
  let!(:app) { FactoryBot.create(:app) }
  let!(:agent_role) { app.add_agent({ email: "agent-m11@example.com" }) }
  let!(:any_request) { stub_request(:any, /.*/).to_return(status: 200, body: "") }

  before do
    allow(MessageApis::SafeDownload).to receive(:resolve).and_return(["93.184.216.34"])
    ActiveJob::Base.queue_adapter = :test
    ActiveJob::Base.queue_adapter.perform_enqueued_at_jobs = false
  end

  # rubocop:disable-next Metrics/BlockLength
  describe "sending" do
    let(:package) { double(settings: { "phones" => "" }) }
    let(:api) { MessageApis::TelnyxSms::Api.new(config: { api_key: "test-key", package: package }) }
    let(:recipient) { app.add_user(email: "mms-recipient@example.com") }
    let(:thread) { app.conversations.create!(main_participant: recipient) }

    before { thread.conversation_channels.create!(provider: "TelnyxSms", provider_channel_id: "15550001111") }

    def doc(*nodes)
      { type: "doc", content: nodes }.to_json
    end

    def text(value)
      { type: "paragraph", content: [{ type: "text", text: value }] }
    end

    def media(type, url)
      { type: type, attrs: { url: url } }
    end

    def build_part(content)
      thread.messages.build(authorable: agent_role.agent,
                            messageable: ConversationPartContent.new(serialized_content: content))
    end

    def deliver(content)
      api.send_message(thread, build_part(content))
    end

    def ok(id)
      { status: 200, body: { data: { id: id } }.to_json, headers: { "Content-Type" => "application/json" } }
    end

    def failure
      body = { errors: [{ code: "40305", title: "Invalid from address", detail: "MMS is not enabled for this number",
                          source: { pointer: "/m11-private-pointer" } }] }
      { status: 422, body: body.to_json, headers: { "Content-Type" => "application/json" } }
    end

    def capture(*responses)
      bodies = []
      queue = responses.empty? ? [ok("out-1")] : responses.dup
      stub = stub_request(:post, endpoint).with(headers: { "Authorization" => "Bearer test-key" })
      stub.to_return do |request|
        bodies << JSON.parse(request.body)
        queue.size > 1 ? queue.shift : queue.first
      end
      [stub, bodies]
    end

    def errored_events
      thread.reload.messages.map(&:messageable).grep(ConversationPartEvent)
            .select { |event| event.action.to_s.start_with?("errored") }
    end

    it "sends every supported attachment with one URL in media_urls per request and the text on the first" do
      stub, bodies = capture
      relative = "/rails/active_storage/blobs/redirect/abc/photo.JPG"
      deliver(doc(text("look at this"), media("ImageBlock", "https://cdn.example.com/a b.png"),
                  media("FileBlock", relative), media("VideoBlock", "https://cdn.example.com/v.mp4")))
      assert_requested(stub, times: 3)
      expected = [["https://cdn.example.com/a%20b.png"], [MessageApis::BlockManager.absolute_url(relative)],
                  ["https://cdn.example.com/v.mp4"]]
      expect(bodies.pluck("media_urls")).to eq(expected)
      expect(bodies.pluck("text")).to eq(["look at this", nil, nil])
      expect(bodies.pluck("to").uniq).to eq(["+15550001111"])
    end

    it "sends an unsupported PDF as a link in the text, not as media" do
      stub, bodies = capture
      relative = "/rails/active_storage/blobs/redirect/abc/report.pdf"
      link = MessageApis::BlockManager.absolute_url(relative)
      deliver(doc(text("see"), media("ImageBlock", "https://cdn.example.com/p.png"), media("FileBlock", relative)))
      assert_requested(stub, times: 1)
      expect(bodies.first["media_urls"]).to eq(["https://cdn.example.com/p.png"])
      expect(bodies.first["text"]).to eq("see\n#{link}")
      deliver(doc(media("FileBlock", relative)))
      expect(bodies.last).not_to have_key("media_urls")
      expect(bodies.last["text"]).to eq(link)
    end

    it "sends a media-only message without a text field" do
      stub, bodies = capture
      deliver(doc(media("ImageBlock", "https://cdn.example.com/only.png")))
      assert_requested(stub, times: 1)
      expect(bodies.first["media_urls"]).to eq(["https://cdn.example.com/only.png"])
      expect(bodies.first).not_to have_key("text")
    end

    it "keeps text-only messages as SMS without media_urls (base-green)" do
      _stub, bodies = capture
      deliver(doc(text("plain")))
      expect(bodies.size).to eq(1)
      expect(bodies.first["text"]).to eq("plain")
      expect(bodies.first).not_to have_key("media_urls")
    end

    it "stores the provider message id of every sent part" do
      capture(ok("40385f64-0000-4562-b3fc-000000000001"), ok("40385f64-0000-4562-b3fc-000000000002"))
      content = doc(text("ids"), media("ImageBlock", "https://cdn.example.com/1.png"),
                    media("ImageBlock", "https://cdn.example.com/2.png"))
      part = thread.messages.create!(authorable: agent_role.agent,
                                     messageable: ConversationPartContent.create!(serialized_content: content))
      api.notify_message(conversation: thread, part: part, channel: nil)
      ids = part.reload.conversation_part_channel_sources.where(provider: "TelnyxSms").pluck(:message_source_id)
      expect(ids).to contain_exactly("40385f64-0000-4562-b3fc-000000000001", "40385f64-0000-4562-b3fc-000000000002")
    end

    it "stores the provider message id of a text-only message" do
      capture(ok("40385f64-0000-4562-b3fc-000000000003"))
      part = thread.messages.create!(authorable: agent_role.agent,
                                     messageable: ConversationPartContent.create!(serialized_content: doc(text("sms"))))
      api.notify_message(conversation: thread, part: part, channel: nil)
      ids = part.reload.conversation_part_channel_sources.where(provider: "TelnyxSms").pluck(:message_source_id)
      expect(ids).to eq(["40385f64-0000-4562-b3fc-000000000003"])
    end

    def persisted_part(content)
      thread.messages.create!(authorable: agent_role.agent,
                              messageable: ConversationPartContent.create!(serialized_content: content))
    end

    it "stores the provider message id of a message whose only attachment is sent as a link" do
      capture(ok("40385f64-0000-4562-b3fc-000000000004"))
      part = persisted_part(doc(media("FileBlock", "https://cdn.example.com/only.pdf")))
      api.notify_message(conversation: thread, part: part, channel: nil)
      ids = part.reload.conversation_part_channel_sources.where(provider: "TelnyxSms").pluck(:message_source_id)
      expect(ids).to eq(["40385f64-0000-4562-b3fc-000000000004"])
    end

    it "does not resend an attachment already delivered on retry" do
      _stub, bodies = capture(ok("40385f64-0000-4562-b3fc-000000000006"))
      part = persisted_part(doc(text("again"), media("ImageBlock", "https://cdn.example.com/1.png"),
                                media("ImageBlock", "https://cdn.example.com/2.png")))
      part.conversation_part_channel_sources.create!(provider: "TelnyxSms", delivery_index: 0,
                                                     message_source_id: "40385f64-0000-4562-b3fc-000000000005")
      api.notify_message(conversation: thread, part: part, channel: nil)
      expect(bodies.pluck("media_urls")).to eq([["https://cdn.example.com/2.png"]])
      expect(bodies.first).not_to have_key("text")
      ids = part.reload.conversation_part_channel_sources.where(provider: "TelnyxSms").pluck(:message_source_id)
      expect(ids).to contain_exactly("40385f64-0000-4562-b3fc-000000000005", "40385f64-0000-4562-b3fc-000000000006")
    end

    it "records a failed send as an errored event without the provider body and returns nil" do
      capture(failure)
      expect(deliver(doc(text("fail"), media("ImageBlock", "https://cdn.example.com/f.png")))).to be_nil
      expect(errored_events).not_to be_empty
      expect(errored_events.map(&:action)).to all(include("Invalid from address").or(include("MMS is not enabled")))
      expect(errored_events.map { |e| e.data.to_json }.join).not_to include("m11-private-pointer")
    end

    it "records a failed later attachment of a partly sent message" do
      capture(ok("out-ok"), failure)
      result = deliver(doc(text("two"), media("ImageBlock", "https://cdn.example.com/1.png"),
                           media("ImageBlock", "https://cdn.example.com/2.png")))
      expect(result).to respond_to(:body)
      expect(errored_events.size).to eq(1)
      expect(errored_events.first.data.to_json).not_to include("m11-private-pointer")
    end
  end

  # rubocop:disable-next Metrics/BlockLength
  describe "receiving and status callbacks" do
    let(:app_package) { AppPackage.find_by(name: "TelnyxSms") }
    let(:settings) { { api_key: "telnyx-secret", profile_id: "1111", phones: "+1-513-203-1070" } }
    let!(:pkg) do
      AppPackagesCatalog.update_all
      allow_any_instance_of(AppPackageIntegration).to receive(:handle_registration).and_return({})
      app.app_package_integrations.create(app_package: app_package, settings: settings)
    end

    def hook(event_type, payload)
      data = { event_type: event_type, id: SecureRandom.uuid, payload: payload, record_type: "event" }
      post(:process_event, params: { data: data, "provider" => "telnyx_sms", "app_key" => app.key,
                                     "id" => pkg.encoded_id }, as: :json)
      perform_enqueued_jobs
      expect(response.status).to eq(200)
    end

    def inbound(id:, text: nil, media: [])
      hook("message.received", { id: id, direction: "inbound", type: media.empty? ? "SMS" : "MMS", text: text,
                                 from: { phone_number: "+15557770000" }, to: [{ phone_number: "+15132031070" }],
                                 media: media })
    end

    def blocks
      content = app.conversations.last.messages.last.messageable.serialized_content
      MessageApis::BlockManager.get_blocks(content)
    end

    def serve(url, body, type)
      stub_request(:get, url).to_return(status: 200, body: body, headers: { "Content-Type" => type })
    end

    it "stores inbound MMS media in Active Storage through SafeDownload" do
      photo = "https://media.telnyx.com/in/photo.png"
      file = "https://media.telnyx.com/in/doc.pdf?X-Amz-Signature=abc"
      png_stub = serve(photo, png, "image/png")
      pdf_stub = serve(file, pdf, "application/pdf")
      expect do
        inbound(id: "in-media-1", text: "two files",
                media: [{ url: photo, content_type: "image/png", size: png.bytesize },
                        { url: file, content_type: "application/pdf" }])
      end.to change(ActiveStorage::Blob, :count).by(2)
      assert_requested(png_stub, times: 1)
      assert_requested(pdf_stub, times: 1)
      expect(blocks.pluck("type")).to include("ImageBlock", "FileBlock")
      urls = blocks.filter_map { |b| b.dig("attrs", "url") }
      expect(urls.size).to eq(2)
      expect(urls).to all(include("/rails/active_storage/"))
      expect(urls.join).not_to include("telnyx")
      expect(MessageApis::BlockManager.plain_text(blocks)).to include("two files")
    end

    def keyed(url)
      stub_request(:get, url).with(headers: { "Authorization" => "Bearer telnyx-secret" })
                             .to_return(status: 200, body: png, headers: { "Content-Type" => "image/png" })
    end

    def image_media(*urls)
      urls.map { |url| { url: url, content_type: "image/png" } }
    end

    it "downloads media with the API key from https telnyx.com hosts" do
      sub = keyed("https://media.telnyx.com/in/a.png")
      apex = keyed("https://telnyx.com/in/b.png")
      upper = keyed("https://mms.media.telnyx.com/in/c.png")
      inbound(id: "in-key", media: image_media("https://media.telnyx.com/in/a.png", "https://telnyx.com/in/b.png",
                                               "https://MMS.Media.Telnyx.COM/in/c.png"))
      [sub, apex, upper].each { |stub| assert_requested(stub, times: 1) }
      expect(blocks.count { |b| b["type"] == "ImageBlock" }).to eq(3)
    end

    it "does not download plain http media even on telnyx.com (base-green)" do
      inbound(id: "in-http", text: "x", media: image_media("http://media.telnyx.com/in/a.png"))
      assert_not_requested(:get, "http://media.telnyx.com/in/a.png")
      expect(blocks.pluck("type")).not_to include("ImageBlock")
    end

    it "does not download media from lookalike hosts (base-green)" do
      urls = %w[https://eviltelnyx.com/a.png https://telnyx.com.evil.com/a.png https://telnyx.co/a.png
                https://media.telnyx.com.evil.com/a.png https://user@evil.com/media.telnyx.com/a.png]
      inbound(id: "in-lookalike", text: "x", media: image_media(*urls))
      urls.each { |url| assert_not_requested(:get, url) }
      expect(ActiveStorage::Blob.count).to eq(0)
    end

    it "does not download media from a foreign host and logs it" do
      allow(Rails.logger).to receive(:warn).and_call_original
      inbound(id: "in-foreign", text: "keep me", media: image_media("https://cdn.example.com/b.png"))
      assert_not_requested(:get, "https://cdn.example.com/b.png")
      expect(Rails.logger).to have_received(:warn).at_least(:once)
      expect(MessageApis::BlockManager.plain_text(blocks)).to include("keep me")
    end

    it "does not send the API key after a redirect, even to the same host" do
      first = stub_request(:get, "https://media.telnyx.com/in/r1.png")
              .with(headers: { "Authorization" => "Bearer telnyx-secret" })
              .to_return(status: 302, headers: { "Location" => "https://media.telnyx.com/in/r2.png" })
      second = stub_request(:get, "https://media.telnyx.com/in/r2.png")
               .with { |r| r.headers["Authorization"].nil? }
               .to_return(status: 200, body: png, headers: { "Content-Type" => "image/png" })
      inbound(id: "in-redirect", media: image_media("https://media.telnyx.com/in/r1.png"))
      assert_requested(first, times: 1)
      assert_requested(second, times: 1)
      expect(blocks.pluck("type")).to eq(["ImageBlock"])
    end

    it "does not download media from a private address and keeps the message (base-green)" do
      allow(MessageApis::SafeDownload).to receive(:resolve).with("media.telnyx.com").and_return(["10.0.0.5"])
      inbound(id: "in-private", text: "hello", media: image_media("https://media.telnyx.com/in/x.png"))
      assert_not_requested(:get, "https://media.telnyx.com/in/x.png")
      expect(ActiveStorage::Blob.count).to eq(0)
      expect(MessageApis::BlockManager.plain_text(blocks)).to include("hello")
      expect(blocks.pluck("type")).not_to include("ImageBlock")
    end

    it "does not use the own host exception of SafeDownload for media (base-green)" do
      allow(Chaskiq::Config).to receive(:get).and_call_original
      allow(Chaskiq::Config).to receive(:get).with("HOST").and_return("https://media.telnyx.com")
      allow(MessageApis::SafeDownload).to receive(:resolve).with("media.telnyx.com").and_return(["10.0.0.5"])
      inbound(id: "in-own", text: "own", media: image_media("https://media.telnyx.com/in/own.png"))
      assert_not_requested(:get, "https://media.telnyx.com/in/own.png")
      expect(ActiveStorage::Blob.count).to eq(0)
    end

    it "accepts a media-only MMS with null text" do
      serve("https://media.telnyx.com/in/only.png", png, "image/png")
      inbound(id: "in-only", media: [{ url: "https://media.telnyx.com/in/only.png", content_type: "image/png" }])
      expect(app.conversations.count).to eq(1)
      expect(blocks.pluck("type")).to eq(["ImageBlock"])
    end

    it "does not store oversized media (base-green)" do
      serve("https://media.telnyx.com/in/big.mp4", "0" * (6 * 1024 * 1024), "video/mp4")
      inbound(id: "in-big", text: "big",
              media: [{ url: "https://media.telnyx.com/in/big.mp4", content_type: "video/mp4" }])
      expect(ActiveStorage::Blob.count).to eq(0)
      expect(blocks.pluck("type")).not_to include("FileBlock")
    end

    it "marks a part read only when message.finalized reports delivered" do
      inbound(id: "status-1", text: "tracked")
      part = app.conversations.last.messages.last
      hook("message.sent", { id: "status-1", to: [{ status: "sent" }] })
      expect(part.reload.read_at).to be_nil
      hook("message.finalized", { id: "status-1", to: [{ status: "delivery_unconfirmed" }] })
      expect(part.reload.read_at).to be_nil
      hook("message.finalized", { id: "status-1", to: [{ status: "delivered" }] })
      expect(part.reload.read_at).to be_present
    end

    it "records a failed delivery once as an errored event without the raw payload" do
      inbound(id: "status-2", text: "tracked")
      conversation = app.conversations.last
      part = conversation.messages.last
      failed = { id: "status-2", to: [{ status: "delivery_failed" }],
                 errors: [{ code: "40002", title: "Destination number not in service",
                            source: { pointer: "/m11-private-pointer" } }] }
      2.times { hook("message.finalized", failed) }
      expect(part.reload.read_at).to be_nil
      events = conversation.reload.messages.map(&:messageable).grep(ConversationPartEvent)
      errored = events.select { |e| e.action.to_s.start_with?("errored") }
      expect(errored.size).to eq(1)
      expect(errored.first.action).to include("Destination number not in service")
      expect(errored.first.data.to_json).not_to include("m11-private-pointer")
    end

    it "ignores status callbacks for a message id of another app" do
      other_app = FactoryBot.create(:app)
      user = other_app.add_user(email: "other-app-user@example.com")
      foreign = other_app.conversations.create!(main_participant: user)
      foreign.add_message(from: user, message: { html_content: "foreign" }, provider: "TelnyxSms",
                          message_source_id: "foreign-1")
      part = foreign.messages.last
      hook("message.finalized", { id: "foreign-1", to: [{ status: "delivered" }] })
      expect(part.reload.read_at).to be_nil
      hook("message.finalized", { id: "foreign-1", to: [{ status: "delivery_failed" }], errors: [{ title: "x" }] })
      actions = foreign.reload.messages.map(&:messageable).grep(ConversationPartEvent).map(&:action)
      expect(actions.grep(/errored/)).to be_empty
    end
  end

  describe "SafeDownload headers" do
    it "sends headers only on the first request and not after a redirect" do
      first = stub_request(:get, "https://media.telnyx.com/r/1")
              .with(headers: { "Authorization" => "Bearer k" })
              .to_return(status: 302, headers: { "Location" => "https://bucket.s3.amazonaws.com/r/1?sig=1" })
      target = stub_request(:get, "https://bucket.s3.amazonaws.com/r/1?sig=1")
               .with { |r| r.headers["Authorization"].nil? }
               .to_return(status: 200, body: "ok", headers: { "Content-Type" => "text/plain" })
      body = MessageApis::SafeDownload.fetch("https://media.telnyx.com/r/1", headers: { "Authorization" => "Bearer k" })
      expect(body&.read).to eq("ok")
      assert_requested(first, times: 1)
      assert_requested(target, times: 1)
    end

    it "does not send headers after a redirect to the same host" do
      first = stub_request(:get, "https://media.telnyx.com/s/1")
              .with(headers: { "Authorization" => "Bearer k" })
              .to_return(status: 301, headers: { "Location" => "/s/2" })
      target = stub_request(:get, "https://media.telnyx.com/s/2")
               .with { |r| r.headers["Authorization"].nil? }
               .to_return(status: 200, body: "same", headers: { "Content-Type" => "text/plain" })
      body = MessageApis::SafeDownload.fetch("https://media.telnyx.com/s/1", headers: { "Authorization" => "Bearer k" })
      expect(body&.read).to eq("same")
      assert_requested(first, times: 1)
      assert_requested(target, times: 1)
    end

    it "keeps the own host exception by default and drops it with allow_own_host: false" do
      allow(Chaskiq::Config).to receive(:get).and_call_original
      allow(Chaskiq::Config).to receive(:get).with("HOST").and_return("https://own.example")
      allow(MessageApis::SafeDownload).to receive(:resolve).with("own.example").and_return(["10.0.0.7"])
      own = stub_request(:get, "https://own.example/f").to_return(status: 200, body: "own")
      expect(MessageApis::SafeDownload.fetch("https://own.example/f")&.read).to eq("own")
      expect(MessageApis::SafeDownload.fetch("https://own.example/f", allow_own_host: false)).to be_nil
      assert_requested(own, times: 1)
    end

    it "sends no extra headers by default (base-green)" do
      plain = stub_request(:get, "https://cdn.example.com/p")
              .with { |r| r.headers["Authorization"].nil? }
              .to_return(status: 200, body: "x")
      expect(MessageApis::SafeDownload.fetch("https://cdn.example.com/p")&.read).to eq("x")
      assert_requested(plain, times: 1)
    end
  end
end
