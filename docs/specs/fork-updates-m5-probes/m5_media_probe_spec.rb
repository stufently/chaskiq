# frozen_string_literal: true

# Probe for fork-updates-m5 (all attachments, safe server-side download).
# Run: bash docs/specs/fork-updates-m5-probes/rspec_gate_m5.sh --only docs/specs/fork-updates-m5-probes/m5_media_probe_spec.rb
# 1. Telegram, Vonage and MessageBird send every media block of an outgoing message, one provider
#    request per media in document order; the text goes once, as the caption of the first sent
#    media; media without a usable URL are skipped; with no sendable media the text goes alone;
#    send_message returns the response of the first request.
# 2. MessageApis::SafeDownload fetches only http(s) URLs whose every resolved address is public,
#    pins the connection to the checked address, ignores proxy env, re-checks every redirect
#    hop, caps redirects and size; the own HOST origin is allowed.
# 3. The Twitter plugin downloads media only through SafeDownload.
require "rails_helper"

RSpec.describe "fork-updates-m5 probe: attachments and safe download", type: :model do
  include WebMock::API

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
  let!(:agent_role) { app.add_agent({ email: "m5probe@example.com" }) }
  let(:recipient) { app.add_user(email: "m5recipient@example.com") }
  let(:thread) { app.conversations.create!(main_participant: recipient) }

  before do
    allow(Chaskiq::Config).to receive(:get).and_call_original
    allow(Chaskiq::Config).to receive(:get).with("HOST").and_return("https://chat.example.com")
  end

  def doc(*nodes) = { type: "doc", content: nodes }.to_json
  def para(text) = { type: "paragraph", content: [{ type: "text", text: text }] }
  def media(type, url) = { type: type, attrs: { url: url } }

  def part_with(content)
    thread.messages.build(authorable: agent_role.agent, messageable: ConversationPartContent.new(serialized_content: content))
  end

  describe "Telegram" do
    let(:api) { MessageApis::Telegram::Api.new(config: { "access_token" => "tok" }) }
    let(:base) { "https://api.telegram.org/bottok" }

    before { thread.conversation_channels.create!(provider: "telegram", provider_channel_id: "123") }

    it "sends every attachment in order with the text once as the first caption" do
      calls = []
      %w[sendPhoto sendVideo sendDocument sendMessage].each do |m|
        stub_request(:post, "#{base}/#{m}").to_return do |req|
          calls << [m, JSON.parse(req.body)]
          { status: 200, body: { "result" => { "message_id" => calls.size } }.to_json }
        end
      end
      content = doc(para("hello"), media("ImageBlock", "/uploads/a.png"), media("ImageBlock", "https://cdn.example.com/b.png"),
                    media("VideoBlock", "/uploads/c.mp4"), media("FileBlock", "/uploads/d.pdf"))
      response = api.send_message(thread, part_with(content))
      expect(calls.map(&:first)).to eq(%w[sendPhoto sendPhoto sendVideo sendDocument])
      expect(calls.map { |c| c[1]["photo"] || c[1]["video"] || c[1]["document"] }).to eq(
        ["https://chat.example.com/uploads/a.png", "https://cdn.example.com/b.png",
         "https://chat.example.com/uploads/c.mp4", "https://chat.example.com/uploads/d.pdf"]
      )
      expect(calls.map { |c| c[1]["caption"].to_s }).to eq(["hello", "", "", ""])
      expect(calls.map { |c| c[1]["chat_id"] }.uniq).to eq(["123"])
      expect(JSON.parse(response.body).dig("result", "message_id")).to eq(1)
    end

    it "skips a media without a usable URL and captions the first sent one" do
      calls = []
      %w[sendPhoto sendMessage].each do |m|
        stub_request(:post, "#{base}/#{m}").to_return do |req|
          calls << [m, JSON.parse(req.body)]
          { status: 200, body: "{}" }
        end
      end
      api.send_message(thread, part_with(doc(para("hi"), media("ImageBlock", "javascript:alert(1)"),
                                             media("ImageBlock", "/uploads/ok.png"))))
      expect(calls.map(&:first)).to eq(%w[sendPhoto])
      expect(calls[0][1]).to include("photo" => "https://chat.example.com/uploads/ok.png", "caption" => "hi")
    end

    it "sends the text alone when no attachment is sendable" do
      calls = []
      %w[sendPhoto sendMessage].each do |m|
        stub_request(:post, "#{base}/#{m}").to_return do |req|
          calls << [m, JSON.parse(req.body)]
          { status: 200, body: "{}" }
        end
      end
      api.send_message(thread, part_with(doc(para("only text"), media("ImageBlock", ""))))
      expect(calls.map(&:first)).to eq(%w[sendMessage])
      expect(calls[0][1]["text"]).to eq("only text")
    end

    it "sends every image of a legacy Draft.js message" do
      calls = []
      stub_request(:post, "#{base}/sendPhoto").to_return do |req|
        calls << JSON.parse(req.body)
        { status: 200, body: "{}" }
      end
      draft = { blocks: %w[/uploads/1.png /uploads/2.png].map.with_index do |u, i|
        { key: "k#{i}", text: "", type: "image", depth: 0, inlineStyleRanges: [], entityRanges: [], data: { url: u } }
      end, entityMap: {} }.to_json
      api.send_message(thread, part_with(draft))
      expect(calls.map { |c| c["photo"] }).to eq(%w[https://chat.example.com/uploads/1.png https://chat.example.com/uploads/2.png])
    end
  end

  describe "Vonage" do
    let(:api) do
      MessageApis::Vonage::Api.new(config: { "api_key" => "k", "api_secret" => "s", "user_id" => "+100", "sandbox" => true })
    end

    before do
      recipient.external_profiles.create!(provider: "vonage", profile_id: "+200")
    end

    it "sends every attachment in order with the text once as the first caption" do
      calls = []
      stub_request(:post, api.instance_variable_get(:@url)).to_return do |req|
        calls << JSON.parse(req.body)
        { status: 200, body: { "message_uuid" => "uuid-#{calls.size}" }.to_json }
      end
      content = doc(media("ImageBlock", "/uploads/a.png"), para("hello"), media("FileBlock", "/uploads/b.pdf"),
                    media("AudioRecorderBlock", "/uploads/c.ogg"))
      response = api.send_message(thread, part_with(content))
      contents = calls.map { |c| c.dig("message", "content") }
      expect(contents.map { |c| c["type"] }).to eq(%w[image file audio])
      expect(contents.map { |c| c[c["type"]]["url"] }).to eq(
        %w[https://chat.example.com/uploads/a.png https://chat.example.com/uploads/b.pdf https://chat.example.com/uploads/c.ogg]
      )
      expect(contents.map { |c| c[c["type"]]["caption"].to_s }).to eq(["hello", "", ""])
      expect(calls.map { |c| c.dig("to", "number") }.uniq).to eq(["+200"])
      expect(JSON.parse(response.body)["message_uuid"]).to eq("uuid-1")
    end

    it "sends the text alone when no attachment is sendable" do
      calls = []
      stub_request(:post, api.instance_variable_get(:@url)).to_return do |req|
        calls << JSON.parse(req.body)
        { status: 200, body: "{}" }
      end
      api.send_message(thread, part_with(doc(para("only text"), media("VideoBlock", "ftp://x.example/v.mp4"))))
      expect(calls.map { |c| c.dig("message", "content") }).to eq([{ "type" => "text", "text" => "only text" }])
    end
  end

  describe "MessageBird" do
    let(:api) do
      MessageApis::MessageBird::Api.new(config: { "api_key" => "k", "user_id" => "+100", "sandbox" => true })
    end

    before do
      recipient.external_profiles.create!(provider: "message_bird", profile_id: "+200")
    end

    it "sends every attachment in order with the text once as the first caption" do
      calls = []
      stub_request(:post, "#{api.instance_variable_get(:@url)}send").to_return do |req|
        calls << JSON.parse(req.body)
        { status: 200, body: { "messages" => [{ "id" => "mb-#{calls.size}" }] }.to_json }
      end
      content = doc(para("hello"), media("VideoBlock", "/uploads/a.mp4"), media("ImageBlock", "/uploads/b.png"))
      response = api.send_message(thread, part_with(content))
      expect(calls.map { |c| c["type"] }).to eq(%w[video image])
      expect(calls.map { |c| c.dig("content", c["type"], "url") }).to eq(
        %w[https://chat.example.com/uploads/a.mp4 https://chat.example.com/uploads/b.png]
      )
      expect(calls.map { |c| c.dig("content", c["type"], "caption").to_s }).to eq(["hello", ""])
      expect(calls.map { |c| c["to"] }.uniq).to eq(["200"])
      expect(JSON.parse(response.body)["messages"].first["id"]).to eq("mb-1")
    end

    it "sends the text alone when no attachment is sendable" do
      calls = []
      stub_request(:post, "#{api.instance_variable_get(:@url)}send").to_return do |req|
        calls << JSON.parse(req.body)
        { status: 200, body: "{}" }
      end
      api.send_message(thread, part_with(doc(para("only text"), media("ImageBlock", "javascript:x"))))
      expect(calls).to eq([{ "from" => "+100", "to" => "200", "type" => "text", "content" => { "text" => "only text" } }])
    end
  end

  describe "SafeDownload.blocked_ip?" do
    %w[127.0.0.1 10.1.2.3 172.16.0.1 172.31.255.255 192.168.1.1 169.254.169.254 100.64.0.1 0.0.0.0
       224.0.0.1 255.255.255.255 198.18.0.1 192.0.0.8 ::1 :: fc00::1 fd12:3456::1 fe80::1 ff02::1
       ::ffff:127.0.0.1 ::ffff:10.0.0.1 ::ffff:169.254.169.254 not-an-ip].each do |ip|
      it("blocks #{ip}") { expect(sd.blocked_ip?(ip)).to be(true) }
    end

    %w[93.184.216.34 8.8.8.8 172.32.0.1 2606:4700::1111 ::ffff:8.8.8.8].each do |ip|
      it("allows #{ip}") { expect(sd.blocked_ip?(ip)).to be(false) }
    end
  end

  describe "SafeDownload.fetch" do
    let(:url) { "https://cdn.example.com/a.png" }

    it "downloads a public URL through a connection pinned to the checked address, without a proxy" do
      allow(sd).to receive(:resolve).with("cdn.example.com").and_return([public_ip])
      stub_request(:get, url).to_return(status: 200, body: "PNGDATA")
      expect(Net::HTTP).to receive(:new).with("cdn.example.com", 443, nil).and_call_original
      expect_any_instance_of(Net::HTTP).to receive(:ipaddr=).with(public_ip).and_call_original
      file = sd.fetch(url)
      expect(file.read).to eq("PNGDATA")
    end

    it "refuses a host that resolves to a private address and makes no request" do
      allow(sd).to receive(:resolve).with("cdn.example.com").and_return(["10.0.0.5"])
      stub = stub_request(:get, url).to_return(status: 200, body: "secret")
      expect(sd.fetch(url)).to be_nil
      assert_not_requested(stub)
    end

    it "refuses a host when any resolved address is private" do
      allow(sd).to receive(:resolve).with("cdn.example.com").and_return([public_ip, "127.0.0.1"])
      stub = stub_request(:get, url).to_return(status: 200, body: "secret")
      expect(sd.fetch(url)).to be_nil
      assert_not_requested(stub)
    end

    it "refuses IP literals in private ranges" do
      stubs = %w[http://127.0.0.1/x http://169.254.169.254/latest/meta-data/ http://[::1]/x http://10.0.0.1:8080/x].map do |u|
        stub_request(:get, u).to_return(status: 200, body: "secret")
      end
      %w[http://127.0.0.1/x http://169.254.169.254/latest/meta-data/ http://[::1]/x http://10.0.0.1:8080/x].each do |u|
        expect(sd.fetch(u)).to be_nil
      end
      stubs.each { |s| assert_not_requested(s) }
    end

    it "refuses non-HTTP schemes without raising" do
      %w[ftp://cdn.example.com/a file:///etc/passwd javascript:alert(1) /relative/path].each do |u|
        expect(sd.fetch(u)).to be_nil
      end
      expect(sd.fetch(nil)).to be_nil
    end

    it "re-checks every redirect hop" do
      allow(sd).to receive(:resolve).with("cdn.example.com").and_return([public_ip])
      allow(sd).to receive(:resolve).with("internal.example").and_return(["10.0.0.9"])
      stub_request(:get, url).to_return(status: 302, headers: { "Location" => "http://internal.example/secret" })
      inner = stub_request(:get, "http://internal.example/secret").to_return(status: 200, body: "secret")
      expect(sd.fetch(url)).to be_nil
      assert_not_requested(inner)
    end

    it "follows up to max_redirects redirects and no more" do
      allow(sd).to receive(:resolve).and_return([public_ip])
      4.times do |i|
        stub_request(:get, "https://cdn.example.com/r#{i}").to_return(status: 302, headers: { "Location" => "/r#{i + 1}" })
      end
      stub_request(:get, "https://cdn.example.com/r4").to_return(status: 200, body: "END")
      expect(sd.fetch("https://cdn.example.com/r1", max_redirects: 3)&.read).to eq("END")
      expect(sd.fetch("https://cdn.example.com/r0", max_redirects: 3)).to be_nil
    end

    it "refuses a body larger than max_bytes" do
      allow(sd).to receive(:resolve).and_return([public_ip])
      stub_request(:get, url).to_return(status: 200, body: "x" * 11)
      expect(sd.fetch(url, max_bytes: 10)).to be_nil
      expect(sd.fetch(url, max_bytes: 11)&.read).to eq("x" * 11)
    end

    it "returns nil on a non-success response" do
      allow(sd).to receive(:resolve).and_return([public_ip])
      stub_request(:get, url).to_return(status: 404, body: "nope")
      expect(sd.fetch(url)).to be_nil
    end

    it "allows the own HOST origin even on a private address, but not another port" do
      allow(Chaskiq::Config).to receive(:get).with("HOST").and_return("http://chaskiq.internal:3000")
      allow(sd).to receive(:resolve).with("chaskiq.internal").and_return(["10.0.0.7"])
      stub_request(:get, "http://chaskiq.internal:3000/rails/a.png").to_return(status: 200, body: "OWN")
      other = stub_request(:get, "http://chaskiq.internal:6379/").to_return(status: 200, body: "redis")
      expect(sd.fetch("http://chaskiq.internal:3000/rails/a.png")&.read).to eq("OWN")
      expect(sd.fetch("http://chaskiq.internal:6379/")).to be_nil
      assert_not_requested(other)
    end
  end

  describe "Twitter media upload" do
    let(:api) do
      MessageApis::Twitter::Api.new(config: { "api_key" => "k", "api_secret" => "s",
                                              "access_token" => "t", "access_token_secret" => "ts" })
    end
    let(:upload) { "https://upload.twitter.com/1.1/media/upload.json" }

    it "does not download a private URL and uploads nothing" do
      secret = stub_request(:get, "http://169.254.169.254/latest/meta-data/").to_return(status: 200, body: "\xFF\xD8\xFF".b)
      up = stub_request(:post, upload).to_return(status: 200, body: { media_id: 1, media_id_string: "1" }.to_json)
      expect(api.upload_media("http://169.254.169.254/latest/meta-data/")).to be_nil
      assert_not_requested(secret)
      assert_not_requested(up)
    end

    it "uploads a public image fetched through SafeDownload" do
      allow(MessageApis::SafeDownload).to receive(:resolve).with("cdn.example.com").and_return([public_ip])
      png = "\x89PNG\r\n\x1A\n".b + ("\x00" * 32).b
      stub_request(:get, "https://cdn.example.com/a.png").to_return(status: 200, body: png)
      up = stub_request(:post, upload).to_return(status: 200, body: { media_id: 7, media_id_string: "7" }.to_json)
      expect(MessageApis::SafeDownload).to receive(:fetch).with("https://cdn.example.com/a.png").and_call_original
      result = api.upload_media("https://cdn.example.com/a.png")
      expect(result["media_id_string"]).to eq("7")
      assert_requested(up, at_least_times: 2)
    end
  end
end
