# frozen_string_literal: true

require "rails_helper"

RSpec.describe MessageApis::Messenger::Api do
  let(:app) { FactoryBot.create(:app) }
  let(:package) do
    double(
      app: app,
      settings: { "verify_token" => "secret" },
      access_token: "tok"
    )
  end

  subject { described_class.new(config: { "access_token" => "tok" }) }

  describe "#create_hook_from_params" do
    it "returns the challenge when mode is subscribe and token matches" do
      params = { "hub.mode" => "subscribe", "hub.verify_token" => "secret", "hub.challenge" => "42" }
      result = subject.send(:create_hook_from_params, params, package)
      expect(result).to eq("42")
    end

    it "returns nil when mode is subscribe but token does not match" do
      params = { "hub.mode" => "subscribe", "hub.verify_token" => "wrong", "hub.challenge" => "42" }
      result = subject.send(:create_hook_from_params, params, package)
      expect(result).to be_nil
    end

    it "returns nil when mode is not subscribe" do
      params = { "hub.mode" => "unsubscribe", "hub.verify_token" => "secret", "hub.challenge" => "42" }
      result = subject.send(:create_hook_from_params, params, package)
      expect(result).to be_nil
    end
  end

  describe "#process_event" do
    it "returns the challenge for subscribe verification" do
      params = {
        "hub.mode" => "subscribe",
        "hub.verify_token" => "secret",
        "hub.challenge" => "42"
      }
      result = subject.send(:process_event, params, package)
      expect(result).to eq("42")
    end

    it "does not call create_hook_from_params when mode is not subscribe" do
      params = {
        "hub.mode" => "other",
        "hub.verify_token" => "secret",
        "hub.challenge" => "42"
      }
      expect(subject).not_to receive(:create_hook_from_params)
      subject.send(:process_event, params, package)
    end
  end

  describe "#attachment_block" do
    it "returns JSON with image blocks for image attachments in order" do
      data = {
        "message" => {
          "attachments" => [
            { "type" => "image", "payload" => { "url" => "http://img1.jpg" } },
            { "type" => "image", "payload" => { "url" => "http://img2.jpg" } }
          ]
        }
      }

      result = subject.send(:attachment_block, data)
      parsed = JSON.parse(result)
      expect(parsed["type"]).to eq("doc")
      expect(parsed["content"].size).to eq(2)
      expect(parsed["content"][0]["attrs"]["url"]).to eq("http://img1.jpg")
      expect(parsed["content"][1]["attrs"]["url"]).to eq("http://img2.jpg")
    end
  end
end
