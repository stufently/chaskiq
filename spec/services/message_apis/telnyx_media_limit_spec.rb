# frozen_string_literal: true

require "rails_helper"
require "webmock"

RSpec.describe MessageApis::TelnyxSms::Api do
  include WebMock::API

  around do |example|
    WebMock.enable!
    example.run
    WebMock.disable!
  end

  let(:app) { FactoryBot.create(:app) }
  let(:pkg) { OpenStruct.new(app: app, settings: { "phones" => "+15551234567" }) }
  let(:config) do
    { "api_key" => "test-key", "profile_id" => "test-profile", :package => pkg }
  end
  let(:api) { described_class.new(config: config) }

  before do
    allow(MessageApis::SafeDownload).to receive(:resolve).and_return(["93.184.216.34"])
  end

  describe "MAX_MEDIA_BYTES (M146)" do
    it "accepts media of 2 KB" do
      body_2k = "x" * 2048
      stub_request(:get, "https://media.telnyx.com/test-file")
        .to_return(status: 200, body: body_2k, headers: { "content-type" => "image/jpeg" })

      result = api.send(:download_media, "https://media.telnyx.com/test-file")
      expect(result).to be_present
    end

    it "rejects media of 5 MB + 1 byte" do
      body_big = "x" * (5 * 1024 * 1024 + 1)
      stub_request(:get, "https://media.telnyx.com/big-file")
        .to_return(status: 200, body: body_big, headers: { "content-type" => "image/jpeg" })

      result = api.send(:download_media, "https://media.telnyx.com/big-file")
      expect(result).to be_nil
    end
  end

  describe "inbound_blocks empty line rejection (M155)" do
    it "rejects empty lines from text" do
      blocks = api.send(:inbound_blocks, "a\n\nb", [], "msg-1")
      text_blocks = blocks.select { |b| b[:type] == "text" }
      expect(text_blocks.size).to eq(2)
      expect(text_blocks.map { |b| b[:text] }).to eq(%w[a b])
    end
  end

  describe "send_sms_message phone normalization (N05/N06)" do
    it "strips leading + and re-adds it" do
      stub_request(:post, described_class::URL)
        .to_return(status: 200, body: '{"data":{}}')

      api.send(:send_sms_message, "15550001", "hi")
      assert_requested(:post, described_class::URL, body: hash_including("to" => "+15550001"))
    end

    it "does not double the + when input already has one" do
      stub_request(:post, described_class::URL)
        .to_return(status: 200, body: '{"data":{}}')

      api.send(:send_sms_message, "+15550001", "hi")
      assert_requested(:post, described_class::URL, body: hash_including("to" => "+15550001"))
    end
  end
end
