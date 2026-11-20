# frozen_string_literal: true

require "rails_helper"
require "webmock"

RSpec.describe "MessageBird get_media" do
  include WebMock::API

  around do |example|
    WebMock.enable!
    example.run
    WebMock.disable!
  end

  let(:config) { { "api_key" => "test-key", "user_id" => "test-user" } }
  let(:api) { MessageApis::MessageBird::Api.new(config: config) }

  describe "#get_media" do
    it "returns nil on successful response (current behavior)" do
      stub_request(:get, %r{.*/media/test-id})
        .to_return(status: 200, body: "file-content")

      result = api.get_media("test-id")
      expect(result).to be_nil
    end

    it "returns the body on failed response (current behavior)" do
      stub_request(:get, %r{.*/media/bad-id})
        .to_return(status: 404, body: "not found")

      result = api.get_media("bad-id")
      expect(result).to eq("not found")
    end
  end
end
