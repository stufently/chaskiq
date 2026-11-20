# frozen_string_literal: true

require "rails_helper"

RSpec.describe MessageApis::BasePackage do
  let(:app) { FactoryBot.create(:app) }
  let(:recipient) { app.add_user(email: "test@example.com") }
  let(:conversation) { app.conversations.create!(main_participant: recipient) }
  let(:part) { conversation.add_message(from: recipient, message: { html_content: "hello" }) }

  let(:plugin_class) do
    klass = Class.new(described_class)
    klass.const_set(:PROVIDER, "test_pkg")
    klass.define_method(:get_message_id) { |data| data["id"] }
    klass
  end
  let(:package) { plugin_class.new(config: {}) }

  describe "#safe_error_code" do
    it "accepts integer error codes" do
      expect(package.send(:safe_error_code, 42)).to eq(42)
    end

    it "accepts short alphanumeric string codes" do
      expect(package.send(:safe_error_code, "ERR-01")).to eq("ERR-01")
    end

    it "rejects nil error codes" do
      expect(package.send(:safe_error_code, nil)).to be_nil
    end

    it "rejects overly long string codes" do
      expect(package.send(:safe_error_code, "a" * 33)).to be_nil
    end

    it "rejects string codes with special characters" do
      expect(package.send(:safe_error_code, "code;drop")).to be_nil
    end
  end

  describe "#error_response_fields" do
    it "extracts error from the errors array" do
      response = double("response", body: '{"errors":[{"code":42,"title":"Bad"}]}')
      _body, error = package.send(:error_response_fields, response)
      expect(error["code"]).to eq(42)
      expect(error["title"]).to eq("Bad")
    end

    it "handles missing errors gracefully" do
      response = double("response", body: "{}")
      _body, error = package.send(:error_response_fields, response)
      expect(error).to eq({})
    end

    it "handles non-array errors" do
      response = double("response", body: '{"errors":"string"}')
      _body, error = package.send(:error_response_fields, response)
      expect(error).to eq({})
    end
  end

  describe "#message_id_for" do
    it "extracts message id from response body" do
      response = double("response", body: '{"id":"msg-123"}')
      expect(package.send(:message_id_for, response)).to eq("msg-123")
    end

    it "returns empty string for missing id" do
      response = double("response", body: "{}")
      expect(package.send(:message_id_for, response)).to be_nil
    end

    it "handles nil response_json" do
      response = double("response", body: "invalid")
      expect(package.send(:message_id_for, response)).to be_nil
    end
  end

  describe "#response_json" do
    it "parses JSON from body method" do
      response = double("response", body: '{"key":"value"}')
      expect(package.send(:response_json, response)).to eq({ "key" => "value" })
    end

    it "parses JSON from string response" do
      expect(package.send(:response_json, '{"key":"value"}')).to eq({ "key" => "value" })
    end

    it "returns nil for invalid JSON" do
      expect(package.send(:response_json, "not json")).to be_nil
    end
  end

  describe "#store_message_id" do
    it "does not store when response indicates failure" do
      response = double("failed", success?: false, body: '{"id":"msg-fail"}')
      package.send(:store_message_id, part, response)
      expect(part.conversation_part_channel_sources.where(provider: "test_pkg").count).to eq(0)
    end

    it "stores message_id when response succeeds" do
      response = double("ok", success?: true, body: '{"id":"msg-ok"}')
      package.send(:store_message_id, part, response)
      source = part.conversation_part_channel_sources.find_by(provider: "test_pkg")
      expect(source).to be_present
      expect(source.message_source_id).to eq("msg-ok")
    end

    it "skips storage when both delivery_index and message_id are nil" do
      response = double("empty", success?: true, body: "{}")
      package.send(:store_message_id, part, response)
      expect(part.conversation_part_channel_sources.where(provider: "test_pkg").count).to eq(0)
    end
  end

  describe "#notify_part" do
    it "skips when delivery source with nil delivery_index exists" do
      part.conversation_part_channel_sources.create!(provider: "test_pkg", message_source_id: "existing")
      expect(package).not_to receive(:send_message)
      package.send(:notify_part, conversation, part)
    end
  end
end
