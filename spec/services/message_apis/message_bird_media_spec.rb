# frozen_string_literal: true

require "rails_helper"

RSpec.describe "MessageBird get_media" do
  let(:config) { { "api_key" => "test-key", "user_id" => "test-user" } }
  let(:api) { MessageApis::MessageBird::Api.new(config: config) }

  describe "#get_media" do
    it "returns the file data on successful download" do
      stub_request(:get, %r{.*/media/test-id})
        .to_return(status: 200, body: "file-content")

      result = api.get_media("test-id")
      expect(result).to eq("file-content")
    end

    it "returns nil on failed response" do
      stub_request(:get, %r{.*/media/bad-id})
        .to_return(status: 404, body: "not found")

      result = api.get_media("bad-id")
      expect(result).to be_nil
    end
  end
end
