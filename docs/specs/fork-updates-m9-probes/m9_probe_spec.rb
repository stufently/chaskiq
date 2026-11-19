# frozen_string_literal: true

# Probe for fork-updates-m9 (visible partial failures, every provider id stored per part).
# Run: bash docs/specs/fork-updates-m9-probes/rspec_gate_m9.sh --only docs/specs/fork-updates-m9-probes/m9_probe_spec.rb
# 1. BlockManager.deliver_attachments(on_success:, on_failure:): on_success gets every successful
#    request (media and text), on_failure every failed request that is NOT the returned result;
#    without the keywords the m7 behaviour and return value are unchanged.
# 2. Telegram, Vonage, MessageBird, Twilio and Dialog360: a failed request in a multi-attachment
#    send that otherwise succeeds adds the "errored: ..." event (provider, bypass-internal source
#    id). Event data is only {status, code, message}: HTTP status, provider error code, error
#    text without URLs and at most 200 characters; the same for Twilio/Dialog360 status
#    callbacks (process_error). A Twilio single failed send is reported once.
# 3. Each provider id is stored as its own ConversationPartChannelSource as soon as its request
#    succeeds; a retried notify_message resumes after the saved ones (rows count = requests
#    already sent) and sends nothing for a finished series or a single text; an id-less success
#    body (Dialog360 {"messages": []}) neither raises nor loses the other ids. Vonage read
#    receipts, Dialog360 read/failed statuses and Twilio read/undelivered callbacks match any
#    attachment, and a part stored before m9 (one row) keeps matching.
require "rails_helper"

# Document builders and a minimal response double for the probe.
module M9ProbeHelpers
  def doc(text, media)
    nodes = [{ type: "text", text: text }] + media.map { |t, u| { type: t, attrs: { url: u } } }
    { type: "doc", content: nodes }.to_json
  end

  Resp = Struct.new(:ok, :tag) do
    def success? = ok
  end
end

# rubocop:disable-next Metrics/BlockLength
RSpec.describe "fork-updates-m9 probe: partial failures and provider ids", type: :model do
  include WebMock::API
  include M9ProbeHelpers

  around do |example|
    WebMock.enable!
    example.run
  ensure
    WebMock.reset!
    WebMock.disable!
  end

  let!(:app) { FactoryBot.create(:app) }
  let!(:agent_role) { app.add_agent({ email: "m9probe@example.com" }) }
  let(:recipient) { app.add_user(email: "m9recipient@example.com") }
  let(:thread) { app.conversations.create!(main_participant: recipient) }
  let(:calls) { [] }
  let(:three) { [["ImageBlock", "/uploads/a.png"], ["FileBlock", "/uploads/b.pdf"], ["VideoBlock", "/uploads/c.mp4"]] }
  let(:bm) { MessageApis::BlockManager }
  let(:media) { [1, 2, 3].map { |i| { "type" => "ImageBlock", "attrs" => { "url" => "https://cdn.example.com/#{i}.png" } } } }

  before do
    allow(Chaskiq::Config).to receive(:get).and_call_original
    allow(Chaskiq::Config).to receive(:get).with("HOST").and_return("https://chat.example.com")
  end

  def resp(success, tag) = M9ProbeHelpers::Resp.new(success, tag)

  def saved_part(text, media)
    thread.add_message(from: agent_role.agent, message: { serialized_content: doc(text, media), html_content: text })
  end

  def errored_events
    thread.reload.messages.select do |m|
      m.messageable.is_a?(ConversationPartEvent) && m.messageable.action.to_s.start_with?("errored:")
    end
  end

  def source_ids(part, provider)
    part.reload.conversation_part_channel_sources.where(provider: provider).pluck(:message_source_id)
  end

  # Stub one provider endpoint. Request n (1-based) gets `replies[n]` when present: a Hash
  # {status:, body:} or :timeout; otherwise status 200 with the body from the block.
  def stub_provider(endpoint, replies = {}, &ok_body)
    stub_request(:post, endpoint).to_return do |req|
      calls << req.body
      reply = replies[calls.size]
      raise Faraday::TimeoutError, "m9 probe timeout" if reply == :timeout

      next { status: reply[:status], body: reply[:body].to_json } if reply

      { status: 200, body: ok_body.call(calls.size).to_json }
    end
  end

  # rubocop:disable-next Metrics/BlockLength
  describe "BlockManager.deliver_attachments" do
    it "keeps the m7 result without the new keywords" do
      seq = [resp(true, :a), resp(false, :b), resp(true, :c)]
      result = bm.deliver_attachments(media, "t", send_text: ->(_) { raise "no text expected" }) { |*| seq.shift }
      expect(result.tag).to eq(:a)
    end

    it "calls on_success for every successful media and text request and on_failure for hidden failures" do
      ok = []
      bad = []
      seq = [resp(false, :a), resp(true, :b), resp(false, :c)]
      result = bm.deliver_attachments(media, "t", send_text: ->(_) { resp(true, :text) }, captionless: %w[ImageBlock],
                                                  on_success: ->(r) { ok << r.tag },
                                                  on_failure: ->(r) { bad << r.tag }) { |*| seq.shift }
      expect(result.tag).to eq(:b)
      expect(ok).to eq(%i[b text])
      expect(bad).to eq(%i[a c])
    end

    it "reports a failed trailing text after a successful attachment" do
      bad = []
      result = bm.deliver_attachments(media.first(1), "t", send_text: ->(_) { resp(false, :text) },
                                                           captionless: %w[ImageBlock],
                                                           on_failure: ->(r) { bad << r.tag }) { |*| resp(true, :m) }
      expect(result.tag).to eq(:m)
      expect(bad).to eq(%i[text])
    end

    it "does not report the failed response it returns" do
      bad = []
      seq = [resp(false, :a), resp(false, :b)]
      result = bm.deliver_attachments(media.first(2), "", send_text: ->(_) { raise "no text" },
                                                          on_failure: ->(r) { bad << r.tag }) { |*| seq.shift }
      expect(result.tag).to eq(:b)
      expect(bad).to eq(%i[a])
    end

    it "reports failed attachments when the fallback text is what gets delivered" do
      bad = []
      ok = []
      result = bm.deliver_attachments(media.first(2), "t", send_text: ->(_) { resp(true, :text) },
                                                           on_success: ->(r) { ok << r.tag },
                                                           on_failure: ->(r) { bad << r.tag }) { |*| resp(false, :m) }
      expect(result.tag).to eq(:text)
      expect(bad).to eq(%i[m m])
      expect(ok).to eq(%i[text])
    end
  end

  describe "Telegram" do
    let(:api) { MessageApis::Telegram::Api.new(config: { "access_token" => "tok" }) }

    before do
      thread.conversation_channels.create!(provider: "telegram", provider_channel_id: "123")
      fail_body = { ok: false, error_code: 400, description: "Bad Request: wrong file" }
      stub_provider(%r{\Ahttps://api\.telegram\.org/bottok/send}, { 2 => { status: 400, body: fail_body } }) do |n|
        { ok: true, result: { message_id: 700 + n } }
      end
    end

    it "reports a failed later attachment with safe event data and stores every message id" do
      part = saved_part("hi", three)
      api.notify_message(conversation: thread, part: part, channel: "123")
      expect(calls.size).to eq(3)
      expect(source_ids(part, "telegram")).to contain_exactly("701", "703")
      ev = errored_events
      expect(ev.map { |e| e.messageable.action }).to eq(["errored: Bad Request: wrong file"])
      expect(ev.first.messageable.data).to eq("status" => 400, "code" => 400, "message" => "Bad Request: wrong file")
    end
  end

  # rubocop:disable-next Metrics/BlockLength
  describe "Vonage" do
    let(:api) { MessageApis::Vonage::Api.new(config: { "sandbox" => true, "user_id" => "100" }) }
    let(:endpoint) { "https://messages-sandbox.nexmo.com/v0.1/messages" }

    before { recipient.external_profiles.create!(provider: "vonage", profile_id: "200") }

    it "stores every message uuid, reports the failed one and matches a read receipt for a later attachment" do
      replies = { 3 => { status: 422, body: { title: "Invalid media" } } }
      stub_provider(endpoint, replies) { |n| { message_uuid: "uuid-#{n}" } }
      part = saved_part("hi", three)
      api.notify_message(conversation: thread, part: part, channel: "200")
      expect(source_ids(part, "vonage")).to contain_exactly("uuid-1", "uuid-2")
      expect(errored_events.map { |e| e.messageable.data })
        .to eq([{ "status" => 422, "code" => nil, "message" => "Invalid media" }])

      api.process_event({ "status" => "read", "message_uuid" => "uuid-2" }, nil)
      expect(part.reload.read_at).to be_present
    end

    it "saves each id as soon as its request succeeds" do
      seen = []
      stub_request(:post, endpoint).to_return do
        seen << ConversationPartChannelSource.where(provider: "vonage").pluck(:message_source_id).sort
        { status: 202, body: { message_uuid: "uuid-#{seen.size}" }.to_json }
      end
      part = saved_part("hi", three)
      api.notify_message(conversation: thread, part: part, channel: "200")
      expect(seen).to eq([[], ["uuid-1"], %w[uuid-1 uuid-2]])
    end

    it "resumes after a timeout on the third of four attachments with only the third and fourth" do
      four = %w[a b c d].map { |n| ["ImageBlock", "/uploads/#{n}.png"] }
      stub_provider(endpoint, { 3 => :timeout }) { |n| { message_uuid: "uuid-#{n}" } }
      part = saved_part("hi", four)
      expect { api.notify_message(conversation: thread, part: part, channel: "200") }.to raise_error(Faraday::TimeoutError)
      expect(source_ids(part, "vonage")).to contain_exactly("uuid-1", "uuid-2")

      api.notify_message(conversation: thread, part: part.reload, channel: "200")
      retried = calls.drop(3).map { |body| JSON.parse(body).dig("message", "content", "image") }
      expect(retried).to eq([{ "url" => "https://chat.example.com/uploads/c.png" },
                             { "url" => "https://chat.example.com/uploads/d.png" }])
      expect(source_ids(part, "vonage")).to contain_exactly("uuid-1", "uuid-2", "uuid-4", "uuid-5")
    end

    it "sends nothing on a retry after a fully delivered series or a single text" do
      stub_provider(endpoint) { |n| { message_uuid: "uuid-#{n}" } }
      media_part = saved_part("hi", three)
      text_part = saved_part("only text", [])
      2.times do
        api.notify_message(conversation: thread, part: media_part, channel: "200")
        api.notify_message(conversation: thread, part: text_part, channel: "200")
      end
      expect(calls.size).to eq(4)
    end

    it "keeps matching a part stored with a single id before m9" do
      part = saved_part("old", [])
      part.conversation_part_channel_sources.create!(provider: "vonage", message_source_id: "legacy-uuid")
      api.process_event({ "status" => "read", "message_uuid" => "legacy-uuid" }, nil)
      expect(part.reload.read_at).to be_present
    end
  end

  describe "MessageBird" do
    let(:api) { MessageApis::MessageBird::Api.new(config: { "sandbox" => true, "user_id" => "100" }) }

    before do
      recipient.external_profiles.create!(provider: "message_bird", profile_id: "+200")
      fail_body = { errors: [{ code: 21, description: "bad media" }] }
      endpoint = "https://whatsapp-sandbox.messagebird.com/v1/send"
      stub_provider(endpoint, { 2 => { status: 422, body: fail_body } }) do |n|
        { id: "mb-#{n}" }
      end
    end

    it "reports a failed later attachment and stores every message id" do
      part = saved_part("hi", three)
      api.notify_message(conversation: thread, part: part, channel: "+200")
      expect(source_ids(part, "message_bird")).to contain_exactly("mb-1", "mb-3")
      expect(errored_events.map { |e| e.messageable.data })
        .to eq([{ "status" => 422, "code" => 21, "message" => "bad media" }])
    end
  end

  # rubocop:disable-next Metrics/BlockLength
  describe "Twilio" do
    let(:api) { MessageApis::Twilio::Api.new(config: { "api_key" => "sid", "api_secret" => "tok", "user_id" => "+100" }) }
    let(:endpoint) { "https://api.twilio.com/2010-04-01/Accounts/sid/Messages.json" }
    let(:twilio_error) do
      { code: 21_620, status: 400, more_info: "https://www.twilio.com/docs/errors/21620",
        message: "Media URL https://chat.example.com/uploads/b.pdf is invalid #{'x' * 300}" }
    end

    before { recipient.external_profiles.create!(provider: "twilio", profile_id: "whatsapp:+200") }

    it "reports a failed later attachment without URLs or the raw body and matches callbacks for every SID" do
      stub_provider(endpoint, { 2 => { status: 400, body: twilio_error } }) { |n| { sid: "SM#{n}" } }
      part = saved_part("hi", three)
      api.notify_message(conversation: thread, part: part, channel: "whatsapp:+200")
      expect(source_ids(part, "twilio")).to contain_exactly("SM1", "SM3")
      ev = errored_events
      expect(ev.size).to eq(1)
      data = ev.first.messageable.data
      expect(data.keys).to contain_exactly("status", "code", "message")
      expect(data).to include("status" => 400, "code" => 21_620)
      expect(data["message"]).to start_with("Media URL [url] is invalid")
      expect(data["message"].size).to be <= 200
      expect(ev.first.messageable.action).to eq("errored: #{data['message']}")
      expect(ev.first.messageable.to_json).not_to include("http")
      expect(ev.first.conversation_part_channel_sources.pluck(:provider, :message_source_id))
        .to eq([["twilio", "bypass-internal-#{part.id}"]])

      api.process_event({ "SmsStatus" => "read", "MessageSid" => "SM3" }, nil)
      expect(part.reload.read_at).to be_present
      api.process_event({ "SmsStatus" => "undelivered", "SmsSid" => "SM3", "id" => "x" }, nil)
      expect(errored_events.map { |e| e.messageable.action }).to include("errored: undelivered")
    end

    it "does not resend the separate text on a retry after audio and text" do
      stub_provider(endpoint) { |n| { sid: "SM#{n}" } }
      part = saved_part("hi", [["AudioRecorderBlock", "/uploads/v.ogg"]])
      2.times { api.notify_message(conversation: thread, part: part, channel: "whatsapp:+200") }
      expect(calls.size).to eq(2)
    end

    it "keeps the status callback event to status, code and a short text" do
      stub_provider(endpoint) { |n| { sid: "SM#{n}" } }
      part = saved_part("hi", three)
      api.notify_message(conversation: thread, part: part, channel: "whatsapp:+200")
      api.process_event({ "SmsStatus" => "undelivered", "SmsSid" => "SM2", "ErrorCode" => "30008", "id" => "x",
                          "To" => "whatsapp:+200", "MediaUrl0" => "https://chat.example.com/uploads/b.pdf" }, nil)
      event = errored_events.last.messageable
      expect(event.action).to eq("errored: undelivered")
      expect(event.data).to eq("status" => nil, "code" => "30008", "message" => "undelivered")
    end

    it "reports a single failed send exactly once in the old action format" do
      replies = { 1 => { status: 400, body: { message: "Unverified number" } } }
      stub_provider(endpoint, replies) { |n| { sid: "SM#{n}" } }
      part = saved_part("hi", [])
      expect(api.notify_message(conversation: thread, part: part, channel: "whatsapp:+200")).to be_nil
      expect(errored_events.map { |e| e.messageable.action }).to eq(["errored: Unverified number"])
      expect(source_ids(part, "twilio")).to be_empty
    end
  end

  describe "Dialog360" do
    let(:api) { MessageApis::Dialog360::Api.new(config: { "api_key" => "k", "user_id" => "100" }) }
    let(:endpoint) { "https://waba.360dialog.io/v1/messages" }

    before { recipient.external_profiles.create!(provider: "dialog_360", profile_id: "200") }

    it "stores every wamid, reports the failed one and matches read and failed statuses for a later attachment" do
      fail_body = { errors: [{ code: 1008, title: "Required parameter is missing" }] }
      stub_provider(endpoint, { 2 => { status: 400, body: fail_body } }) { |n| { messages: [{ id: "wamid.#{n}" }] } }
      part = saved_part("hi", three)
      api.notify_message(conversation: thread, part: part, channel: "200")
      expect(source_ids(part, "dialog_360")).to contain_exactly("wamid.1", "wamid.3")
      expect(errored_events.map { |e| e.messageable.data })
        .to eq([{ "status" => 400, "code" => 1008, "message" => "Required parameter is missing" }])

      api.process_event({ "statuses" => [{ "id" => "wamid.3", "status" => "read" }] }, nil)
      expect(part.reload.read_at).to be_present
      failed = { "id" => "wamid.3", "status" => "failed", "errors" => [{ "code" => 470, "title" => "Re-engagement" }] }
      api.process_event({ "statuses" => [failed] }, nil)
      expect(errored_events.map { |e| e.messageable.action }).to include("errored: 470 Re-engagement")
    end

    it "keeps the failed status event to status, code and a short text" do
      stub_provider(endpoint) { |n| { messages: [{ id: "wamid.#{n}" }] } }
      api.notify_message(conversation: thread, part: saved_part("hi", three), channel: "200")
      errors = [{ "code" => 470, "title" => "see https://developers.facebook.com/x #{'z' * 300}",
                  "href" => "https://developers.facebook.com/docs/whatsapp/api/errors/" }]
      api.process_event({ "statuses" => [{ "id" => "wamid.2", "status" => "failed", "errors" => errors }] }, nil)
      data = errored_events.last.messageable.data
      expect(data.keys).to contain_exactly("status", "code", "message")
      expect(data).to include("status" => nil, "code" => 470)
      expect(data["message"]).to start_with("470 see [url] zzz")
      expect(data["message"].size).to be <= 200
    end

    it "survives a success body without an id and keeps the other ids" do
      replies = { 1 => { status: 201, body: { messages: [] } } }
      stub_provider(endpoint, replies) { |n| { messages: [{ id: "wamid.#{n}" }] } }
      part = saved_part("hi", three)
      expect { api.notify_message(conversation: thread, part: part, channel: "200") }.not_to raise_error
      expect(source_ids(part, "dialog_360")).to contain_exactly("wamid.2", "wamid.3")
    end
  end
end
