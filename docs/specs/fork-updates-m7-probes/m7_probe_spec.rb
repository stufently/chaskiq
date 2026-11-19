# frozen_string_literal: true

# Probe for fork-updates-m7 (all attachments in Twilio and Dialog360, SafeDownload everywhere).
# Run: bash docs/specs/fork-updates-m7-probes/rspec_gate_m7.sh --only docs/specs/fork-updates-m7-probes/m7_probe_spec.rb
# 1. Twilio (WhatsApp) and Dialog360 send every media block, one provider request per media in
#    document order; the text goes once, as the caption of the first sent captioned media; audio
#    never carries a caption (the text then goes as its own message); no media -> text alone.
# 2. BlockManager.deliver_attachments keeps its m5 behaviour without `captionless:`.
# 3. MessageApis::SafeDownload.fetch returns a StringIO with content_type / mime_type.
# 4. SNS SubscribeURL is fetched only for https://sns.<region>.amazonaws.com(.cn) via SafeDownload.
# 5. FetchLinkCardService and Mutations::CreateUrlUpload download only through SafeDownload.
require "rails_helper"

module M7ProbeHelpers
  def doc(*nodes) = { type: "doc", content: nodes }.to_json
  def para(text) = { type: "paragraph", content: [{ type: "text", text: text }] }
  def media(type, url) = { type: type, attrs: { url: url } }

  Resp = Struct.new(:ok, :tag) do
    def success? = ok
  end
end

RSpec.describe "fork-updates-m7 probe: attachments and safe downloads", type: :model do
  include WebMock::API
  include M7ProbeHelpers

  around do |example|
    WebMock.enable!
    example.run
  ensure
    WebMock.reset!
    WebMock.disable!
  end

  let(:sd) { MessageApis::SafeDownload }
  let(:public_ip) { "93.184.216.34" }
  let!(:app) { FactoryBot.create(:app) }
  let!(:agent_role) { app.add_agent({ email: "m7probe@example.com" }) }
  let(:recipient) { app.add_user(email: "m7recipient@example.com") }
  let(:thread) { app.conversations.create!(main_participant: recipient) }

  before do
    allow(Chaskiq::Config).to receive(:get).and_call_original
    allow(Chaskiq::Config).to receive(:get).with("HOST").and_return("https://chat.example.com")
  end

  def part_with(content)
    thread.messages.build(authorable: agent_role.agent, messageable: ConversationPartContent.new(serialized_content: content))
  end

  describe "Twilio" do
    let(:api) { MessageApis::Twilio::Api.new(config: { "api_key" => "sid", "api_secret" => "tok", "user_id" => "+100" }) }
    let(:endpoint) { "https://api.twilio.com/2010-04-01/Accounts/sid/Messages.json" }
    let(:calls) { [] }

    before do
      recipient.external_profiles.create!(provider: "twilio", profile_id: "whatsapp:+200")
      stub_request(:post, endpoint).to_return do |req|
        calls << Rack::Utils.parse_query(req.body)
        { status: 201, body: { "sid" => "SM#{calls.size}" }.to_json }
      end
    end

    it "sends every attachment, one request each, with the text once as the first caption" do
      content = doc(para("hello"), media("ImageBlock", "/uploads/a b.png"),
                    media("VideoBlock", "https://cdn.example.com/v.mp4"), media("FileBlock", "/uploads/f.pdf"))
      api.send_message(thread, part_with(content))
      expect(calls.map { |c| c["MediaUrl"] }).to eq(["https://chat.example.com/uploads/a%20b.png",
                                                     "https://cdn.example.com/v.mp4",
                                                     "https://chat.example.com/uploads/f.pdf"])
      expect(calls.map { |c| c["Body"] }).to eq(["hello", nil, nil])
      expect(calls.map { |c| c["To"] }.uniq).to eq(["whatsapp:+200"])
    end

    it "never puts the caption on audio and sends the text as its own message" do
      api.send_message(thread, part_with(doc(para("listen"), media("AudioRecorderBlock", "/uploads/a.mp3"))))
      expect(calls.size).to eq(2)
      expect(calls[0]).to include("MediaUrl" => "https://chat.example.com/uploads/a.mp3")
      expect(calls[0]).not_to have_key("Body")
      expect(calls[1]).to include("Body" => "listen")
      expect(calls[1]).not_to have_key("MediaUrl")
    end

    it "sends a text-only message once" do
      api.send_message(thread, part_with(doc(para("only text"))))
      expect(calls).to eq([{ "From" => "whatsapp:+100", "To" => "whatsapp:+200", "Body" => "only text" }])
    end
  end

  describe "Dialog360" do
    let(:api) { MessageApis::Dialog360::Api.new(config: { "api_key" => "k", "user_id" => "100" }) }
    let(:calls) { [] }

    before do
      recipient.external_profiles.create!(provider: "dialog_360", profile_id: "200")
      stub_request(:post, "https://waba.360dialog.io/v1/messages").to_return do |req|
        calls << JSON.parse(req.body)
        { status: 201, body: { "messages" => [{ "id" => "wamid.#{calls.size}" }] }.to_json }
      end
    end

    it "sends every attachment typed, with the text once as the first caption and no caption on audio" do
      content = doc(para("hi"), media("AudioRecorderBlock", "/uploads/a.ogg"), media("ImageBlock", "/uploads/i.png"),
                    media("VideoBlock", "/uploads/v.mp4"), media("FileBlock", "https://cdn.example.com/d.pdf"))
      api.send_message(thread, part_with(content))
      expect(calls.map { |c| c["type"] }).to eq(%w[audio image video document])
      expect(calls[0]["audio"]).to eq("link" => "https://chat.example.com/uploads/a.ogg")
      expect(calls[1]["image"]).to eq("link" => "https://chat.example.com/uploads/i.png", "caption" => "hi")
      expect(calls[2]["video"]).to eq("link" => "https://chat.example.com/uploads/v.mp4")
      expect(calls[3]["document"]).to eq("link" => "https://cdn.example.com/d.pdf")
      expect(calls.map { |c| c["to"] }.uniq).to eq(["200"])
    end

    it "sends the text after an audio-only message" do
      api.send_message(thread, part_with(doc(para("voice"), media("AudioRecorderBlock", "/uploads/a.ogg"))))
      expect(calls.map { |c| c["type"] }).to eq(%w[audio text])
      expect(calls[1]["text"]).to eq("body" => "voice")
    end

    it "sends a text-only message once" do
      api.send_message(thread, part_with(doc(para("plain"))))
      expect(calls.size).to eq(1)
      expect(calls[0]).to include("type" => "text", "text" => { "body" => "plain" })
    end
  end

  describe "BlockManager.deliver_attachments" do
    it "keeps the m5 behaviour when captionless is not given" do
      seen = []
      texts = []
      blocks = JSON.parse([media("AudioRecorderBlock", "https://cdn.example.com/a.mp3"), media("ImageBlock", "https://cdn.example.com/i.png")].to_json)
      res = MessageApis::BlockManager.deliver_attachments(blocks, "t", send_text: ->(x) { texts << x }) do |type, _url, caption|
        seen << [type, caption]
        M7ProbeHelpers::Resp.new(true, type)
      end
      expect(seen).to eq([["AudioRecorderBlock", "t"], ["ImageBlock", nil]])
      expect(texts).to eq([])
      expect(res.tag).to eq("AudioRecorderBlock")
    end
  end

  describe "SafeDownload body" do
    it "returns a StringIO carrying the response content type" do
      allow(sd).to receive(:resolve).with("cdn.example.com").and_return([public_ip])
      stub_request(:get, "https://cdn.example.com/p.html")
        .to_return(status: 200, body: "<html></html>", headers: { "Content-Type" => "Text/HTML; charset=UTF-8" })
      body = sd.fetch("https://cdn.example.com/p.html")
      expect(body).to be_a(StringIO)
      expect(body.read).to eq("<html></html>")
      expect(body.content_type).to eq("Text/HTML; charset=UTF-8")
      expect(body.mime_type).to eq("text/html")
    end

    it "has a nil mime type without a Content-Type header" do
      allow(sd).to receive(:resolve).with("cdn.example.com").and_return([public_ip])
      stub_request(:get, "https://cdn.example.com/raw").to_return(status: 200, body: "x")
      expect(sd.fetch("https://cdn.example.com/raw").mime_type).to be_nil
    end
  end

  describe "FetchLinkCardService" do
    let(:page) do
      '<html><head><title>T</title><meta property="og:title" content="OG title">' \
        '<meta property="og:image" content="http://intranet.example/i.png"></head></html>'
    end

    before { allow(OEmbed::Providers).to receive(:get).and_raise(OEmbed::NotFound) }

    it "makes no request for a page on a private address" do
      allow(sd).to receive(:resolve).with("intranet.example").and_return(["10.1.2.3"])
      head = stub_request(:head, "http://intranet.example/")
      get = stub_request(:get, "http://intranet.example/")
      expect(FetchLinkCardService.new.call("http://intranet.example/")).to be_nil
      assert_not_requested(head)
      assert_not_requested(get)
    end

    it "builds the card from one safe GET and skips a private og:image" do
      allow(sd).to receive(:resolve).with("site.example.com").and_return([public_ip])
      allow(sd).to receive(:resolve).with("intranet.example").and_return(["10.1.2.3"])
      get = stub_request(:get, "https://site.example.com/a")
            .to_return(status: 200, body: page, headers: { "Content-Type" => "text/html; charset=utf-8" })
      image = stub_request(:get, "http://intranet.example/i.png")
      card = FetchLinkCardService.new.call("https://site.example.com/a")
      expect(card.title).to eq("OG title")
      assert_requested(get, times: 1)
      assert_not_requested(image)
    end

    it "returns nil for a non-HTML page" do
      allow(sd).to receive(:resolve).with("site.example.com").and_return([public_ip])
      stub_request(:get, "https://site.example.com/f.pdf").to_return(status: 200, body: "%PDF", headers: { "Content-Type" => "application/pdf" })
      expect(FetchLinkCardService.new.call("https://site.example.com/f.pdf")).to be_nil
    end
  end

  describe "Mutations::CreateUrlUpload" do
    let(:mutation) { Mutations::CreateUrlUpload.new(object: nil, context: {}, field: nil) }

    it "refuses a private URL without requesting it" do
      allow(sd).to receive(:resolve).with("intranet.example").and_return(["192.168.1.10"])
      stub = stub_request(:get, "http://intranet.example/secret.png")
      expect { mutation.resolve(input: OpenStruct.new(url: "http://intranet.example/secret.png")) }
        .to raise_error(GraphQL::ExecutionError)
      assert_not_requested(stub)
    end

    it "uploads a public URL" do
      allow(sd).to receive(:resolve).with("cdn.example.com").and_return([public_ip])
      stub_request(:get, "https://cdn.example.com/p.png").to_return(status: 200, body: "PNGDATA", headers: { "Content-Type" => "image/png" })
      res = mutation.resolve(input: OpenStruct.new(url: "https://cdn.example.com/p.png"))
      expect(ActiveStorage::Blob.find(res[:direct_upload][:blob_id]).download).to eq("PNGDATA")
    end
  end
end

RSpec.describe Api::V1::HooksController, type: :controller do
  include WebMock::API

  around do |example|
    WebMock.enable!
    example.run
  ensure
    WebMock.reset!
    WebMock.disable!
  end

  def confirm(url)
    request.headers["x-amz-sns-message-type"] = "SubscriptionConfirmation"
    post :create, body: { "Type" => "SubscriptionConfirmation", "SubscribeURL" => url }.to_json
  end

  it "m7 probe: confirms an SNS subscription through SafeDownload" do
    allow(MessageApis::SafeDownload).to receive(:resolve).with("sns.us-east-1.amazonaws.com").and_return(["54.239.1.1"])
    url = "https://sns.us-east-1.amazonaws.com/?Action=ConfirmSubscription&Token=t"
    stub = stub_request(:get, url).to_return(status: 200, body: "<ok/>")
    confirm(url)
    expect(response.body).to eq("ok")
    assert_requested(stub, times: 1)
  end

  [
    "http://169.254.169.254/latest/meta-data/",
    "http://sns.us-east-1.amazonaws.com/?Action=ConfirmSubscription",
    "https://sns.us-east-1.amazonaws.com.evil.example/x",
    "https://evil.example/?sns.us-east-1.amazonaws.com"
  ].each do |url|
    it "m7 probe: never requests a non-SNS SubscribeURL #{url}" do
      allow(MessageApis::SafeDownload).to receive(:resolve).and_return(["54.239.1.1"])
      stub = stub_request(:any, /.*/)
      confirm(url)
      expect(response.body).to eq("ok")
      assert_not_requested(stub)
    end
  end
end
