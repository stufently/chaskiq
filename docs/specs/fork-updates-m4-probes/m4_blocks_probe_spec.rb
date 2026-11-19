# frozen_string_literal: true

# Probe for fork-updates-m4 (outgoing plugin content).
# Run: bash docs/specs/fork-updates-m4-probes/rspec_gate_m4.sh --only docs/specs/fork-updates-m4-probes/m4_blocks_probe_spec.rb
# 1. MessageApis::BlockManager.get_blocks understands the Dante document, the legacy
#    {"blocks": [...]} wrapper that inbound plugins still write (Dante nodes inside), and old
#    Draft.js blocks (key/text/type/data).
# 2. MessageApis::BlockManager.plain_text puts a newline between block nodes and joins inline
#    text nodes as they are.
# 3. MessageApis::BlockManager.absolute_url builds a valid absolute URL from relative paths and
#    paths with spaces or non-ASCII characters, without double-encoding.
# 4. Telegram, Vonage, MessageBird and TelnyxSms relay legacy content (as the Slack and Telegram
#    inbound serializers write it); Slack escapes &, < and > in mrkdwn sections.
require "rails_helper"

RSpec.describe "fork-updates-m4 probe: outgoing plugin content", type: :model do
  include WebMock::API

  around do |example|
    WebMock.enable!
    example.run
  ensure
    WebMock.reset!
    WebMock.disable!
  end

  let(:bm) { MessageApis::BlockManager }
  let(:host) { Chaskiq::Config.get("HOST").to_s.chomp("/") }
  let!(:app) { FactoryBot.create(:app) }
  let!(:agent_role) { app.add_agent({ email: "m4probe@example.com" }) }
  let(:recipient) { app.add_user(email: "m4recipient@example.com") }
  let(:thread) { app.conversations.create!(main_participant: recipient) }

  def doc(*nodes) = { type: "doc", content: nodes }.to_json
  def para(*texts) = { type: "paragraph", content: texts.map { |t| t.is_a?(Hash) ? t : { type: "text", text: t } } }

  # exactly what MessageApis::Slack::Api#process_blocks stores for an inbound Slack message
  def slack_inbound(text)
    MessageApis::Slack::Api.new(config: { "access_token" => "x" }).send(:process_blocks, { "text" => text, "blocks" => [] })
  end

  def draft_js(text)
    { blocks: [{ key: "abc12", text: text, type: "unstyled", depth: 0, inlineStyleRanges: [],
                 entityRanges: [], data: {} }], entityMap: {} }.to_json
  end

  def part_with(content)
    thread.messages.build(authorable: agent_role.agent, messageable: ConversationPartContent.new(serialized_content: content))
  end

  describe "BlockManager.get_blocks" do
    it "returns the content of a Dante document" do
      expect(bm.get_blocks(doc(para("foobar")))).to eq([JSON.parse(para("foobar").to_json)])
    end

    it "returns the nodes of the legacy blocks wrapper written by the Slack inbound serializer" do
      blocks = bm.get_blocks(slack_inbound("foobar"))
      expect(blocks).to be_a(Array)
      expect(bm.plain_text(blocks)).to eq("foobar")
    end

    it "keeps media nodes of the legacy wrapper readable through block_data" do
      content = { blocks: [{ type: "text", text: "see" },
                           { type: "ImageBlock", content: [], attrs: { url: "/uploads/a.png" } }], entityMap: {} }.to_json
      blocks = bm.get_blocks(content)
      image = blocks.find { |b| b["type"] == "ImageBlock" }
      expect(bm.block_data(image)["url"]).to eq("/uploads/a.png")
      expect(bm.plain_text(blocks)).to eq("see")
    end

    it "converts Draft.js text and image blocks" do
      content = { blocks: [
        { key: "k1", text: "hello", type: "unstyled", depth: 0, inlineStyleRanges: [], entityRanges: [], data: {} },
        { key: "k2", text: "", type: "image", depth: 0, inlineStyleRanges: [], entityRanges: [],
          data: { url: "/uploads/b.png" } }
      ], entityMap: {} }.to_json
      blocks = bm.get_blocks(content)
      expect(bm.plain_text(blocks)).to eq("hello")
      image = blocks.find { |b| b["type"] == "ImageBlock" }
      expect(image).not_to be_nil
      expect(bm.block_data(image)["url"]).to eq("/uploads/b.png")
    end

    it "returns nil for JSON that is neither a document nor a blocks wrapper" do
      %w[{} [] null 42 {"blocks":null} {"content":"x"}].each do |raw|
        expect(bm.get_blocks(raw)).to be_nil, "for #{raw}"
      end
    end
  end

  describe "BlockManager.plain_text" do
    it "separates paragraphs with a newline" do
      expect(bm.plain_text(bm.get_blocks(doc(para("заказ"), para("123"))))).to eq("заказ\n123")
    end

    it "joins inline text nodes without inserting characters" do
      bold = { type: "text", text: "123", marks: [{ type: "bold" }] }
      expect(bm.plain_text(bm.get_blocks(doc(para("заказ ", bold))))).to eq("заказ 123")
      expect(bm.plain_text(bm.get_blocks(doc(para("foo", { type: "text", text: "bar", marks: [{ type: "bold" }] }))))).to eq("foobar")
    end

    it "skips empty blocks and separates list items" do
      list = { type: "bulletList", content: [{ type: "listItem", content: [para("one")] },
                                             { type: "listItem", content: [para("two")] }] }
      expect(bm.plain_text(bm.get_blocks(doc(para("a"), { type: "paragraph" }, list, para("b"))))).to eq("a\none\ntwo\nb")
    end

    it "keeps the line structure of top-level text nodes" do
      expect(bm.plain_text(bm.get_blocks(doc({ type: "text", text: "one" }, { type: "text", text: "two" })))).to eq("one\ntwo")
    end
  end

  describe "BlockManager.absolute_url" do
    it "prefixes relative paths with HOST" do
      expect(bm.absolute_url("/rails/a.png")).to eq("#{host}/rails/a.png")
      expect(bm.absolute_url("rails/a.png")).to eq("#{host}/rails/a.png")
    end

    it "encodes spaces and non-ASCII characters without double-encoding" do
      expect(bm.absolute_url("/rails/my file.png")).to eq("#{host}/rails/my%20file.png")
      expect(bm.absolute_url("/rails/my%20file.png")).to eq("#{host}/rails/my%20file.png")
      expect(bm.absolute_url("https://cdn.example.com/a b.png")).to eq("https://cdn.example.com/a%20b.png")
      url = bm.absolute_url("/rails/файл.png")
      expect(URI.parse(url).host).to eq(URI.parse(host).host)
      expect(URI.decode_www_form_component(URI.parse(url).path)).to eq("/rails/файл.png")
    end

    it "returns nil for a blank url" do
      expect(bm.absolute_url("")).to be_nil
      expect(bm.absolute_url(nil)).to be_nil
    end
  end

  describe "relaying legacy content" do
    def stub_json(endpoint, &check)
      stub_request(:post, endpoint).with { |r| check.call(JSON.parse(r.body)) }.to_return(status: 200, body: "{}")
    end

    it "telegram relays Slack-inbound and Draft.js content and keeps paragraphs apart" do
      api = MessageApis::Telegram::Api.new(config: { "access_token" => "m4bot" })
      thread.conversation_channels.create!(provider: "telegram", provider_channel_id: "123")
      url = "https://api.telegram.org/botm4bot/sendMessage"
      s1 = stub_json(url) { |b| b["text"] == "foobar" }
      api.send_message(thread, part_with(slack_inbound("foobar")))
      assert_requested(s1)
      s2 = stub_json(url) { |b| b["text"] == "draft text" }
      api.send_message(thread, part_with(draft_js("draft text")))
      assert_requested(s2)
      s3 = stub_json(url) { |b| b["text"] == "заказ\n123" }
      api.send_message(thread, part_with(doc(para("заказ"), para("123"))))
      assert_requested(s3)
    end

    it "telegram sends a relative image path with a space as a valid absolute URL" do
      api = MessageApis::Telegram::Api.new(config: { "access_token" => "m4bot" })
      thread.conversation_channels.create!(provider: "telegram", provider_channel_id: "123")
      s = stub_json("https://api.telegram.org/botm4bot/sendPhoto") { |b| b["photo"] == "#{host}/uploads/my%20photo.png" }
      api.send_message(thread, part_with(doc({ type: "ImageBlock", attrs: { url: "/uploads/my photo.png" } })))
      assert_requested(s)
    end

    it "vonage relays Slack-inbound content" do
      api = MessageApis::Vonage::Api.new(config: { "sandbox" => true, "user_id" => "111" })
      recipient.external_profiles.create!(provider: "vonage", profile_id: "222")
      s = stub_json("https://messages-sandbox.nexmo.com/v0.1/messages") { |b| b.dig("message", "content", "text") == "foobar" }
      api.send_message(thread, part_with(slack_inbound("foobar")))
      assert_requested(s)
    end

    it "message_bird relays Slack-inbound content" do
      api = MessageApis::MessageBird::Api.new(config: { "sandbox" => true, "user_id" => "111" })
      recipient.external_profiles.create!(provider: "message_bird", profile_id: "222")
      s = stub_json("https://whatsapp-sandbox.messagebird.com/v1/send") { |b| b.dig("content", "text") == "foobar" }
      api.send_message(thread, part_with(slack_inbound("foobar")))
      assert_requested(s)
    end

    it "telnyx_sms relays Slack-inbound content" do
      api = MessageApis::TelnyxSms::Api.new(config: { api_key: "m4key", package: double(settings: { "phones" => "" }) })
      thread.conversation_channels.create!(provider: "TelnyxSms", provider_channel_id: "123")
      s = stub_json("https://api.telnyx.com/v2/messages") { |b| b["text"] == "foobar" }
      api.send_message(thread, part_with(slack_inbound("foobar")))
      assert_requested(s)
    end

    it "slack escapes mrkdwn control characters and relays legacy content" do
      api = MessageApis::Slack::Api.new(config: { "access_token" => "t", "channel_id" => "channel" })
      thread.conversation_channels.create!(provider: "slack", provider_channel_id: "123")
      sections = ->(b) { b.fetch("blocks").map { |x| x.dig("text", "text") } }
      s1 = stub_json("https://slack.com/api/chat.postMessage") { |b| sections.call(b) == ["a &lt;b&gt; &amp; c"] }
      api.notify_message(conversation: thread, part: part_with(doc(para("a <b> & c"))), channel: "channel")
      assert_requested(s1)
      WebMock.reset!
      s2 = stub_json("https://slack.com/api/chat.postMessage") { |b| sections.call(b) == ["foobar"] }
      api.notify_message(conversation: thread, part: part_with(draft_js("foobar")), channel: "channel")
      assert_requested(s2)
    end
  end
end
