# frozen_string_literal: true

require "rails_helper"
require "webmock"

RSpec.describe MessageApis::Slack::Api do
  include WebMock::API

  let(:api) { described_class.new(config: { "access_token" => "x" }) }

  around do |example|
    WebMock.enable!
    example.run
  ensure
    WebMock.reset!
    WebMock.disable!
  end

  before do
    allow(api).to receive(:authorize_bot!)
  end

  describe "#get_slack_user_by_email" do
    it "returns user object from slack response" do
      stub_request(:get, "https://slack.com/api/users.lookupByEmail?email=user%40test.cl")
        .to_return(status: 200, body: { ok: true, user: { id: "U123", name: "testuser" } }.to_json)

      result = api.get_slack_user_by_email("user@test.cl")
      expect(result).to eq({ "id" => "U123", "name" => "testuser" })
    end

    it "returns nil for non-JSON response" do
      stub_request(:get, "https://slack.com/api/users.lookupByEmail?email=bad%40test.cl")
        .to_return(status: 200, body: "not json")

      result = api.get_slack_user_by_email("bad@test.cl")
      expect(result).to be_nil
    end
  end

  describe "#serialize_content" do
    before do
      allow(api).to receive(:attachment_block).and_return("attachments")
      allow(api).to receive(:process_blocks).and_return("blocks")
    end

    it "returns attachment_block when data has files key" do
      result = api.serialize_content({ "files" => [{ "id" => "F1" }] })
      expect(result).to eq("attachments")
    end

    it "returns process_blocks when data has no files key" do
      result = api.serialize_content({ "blocks" => [{ "type" => "section" }] })
      expect(result).to eq("blocks")
    end
  end
end
