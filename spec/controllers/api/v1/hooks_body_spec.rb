# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::HooksController, type: :controller do
  describe "response body" do
    it "returns 'ok' for non-notification requests" do
      body = { "Type" => "Unknown" }.to_json
      allow(MessageApis::SnsMessageVerifier).to receive(:verify!)

      post :create, body: body, as: :json
      expect(response.body).to eq("ok")
    end

    it "returns 'ok' for SNS notification messages" do
      body = {
        "Type" => "Notification",
        "MessageId" => "test-msg-#{SecureRandom.hex(4)}",
        "Subject" => "Test",
        "Message" => "test message"
      }.to_json
      allow(MessageApis::SnsMessageVerifier).to receive(:verify!)

      post :create, body: body, as: :json
      expect(response.body).to eq("ok")
    end
  end
end
