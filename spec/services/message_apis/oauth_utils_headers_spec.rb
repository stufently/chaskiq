# frozen_string_literal: true

require "rails_helper"

RSpec.describe MessageApis::OauthUtils, type: :service do
  describe "HEADERS constant" do
    it "has the expected content" do
      expect(described_class::HEADERS).to eq({ "content-type" => "application/json" })
    end

    it "is frozen" do
      expect(described_class::HEADERS).to be_frozen
    end
  end

  describe "#make_post_request" do
    let(:instance) { Class.new { include MessageApis::OauthUtils }.new }
    let(:client) { double }
    let(:response) { double(code: "200", body: "ok") }

    before do
      instance.instance_variable_set(:@client, client)
    end

    it "passes the HEADERS to the POST request" do
      expect(client).to receive(:post).with(
        "/path", "{}", { "content-type" => "application/json" }
      ).and_return(response)

      expect(instance.make_post_request("/path", "{}")).to eq("ok")
    end
  end
end
