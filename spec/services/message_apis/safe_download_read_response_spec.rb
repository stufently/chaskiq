# frozen_string_literal: true

require "rails_helper"

RSpec.describe MessageApis::SafeDownload do
  describe ".read_response" do
    let(:response) { Net::HTTPOK.new("1.1", "200", "OK") }

    it "ignores the body of an unsuccessful response" do
      missing = Net::HTTPNotFound.new("1.1", "404", "Not Found")
      allow(missing).to receive(:read_body).and_yield("gone")

      expect(described_class.send(:read_response, missing, 4)).to be_nil
      expect(missing).not_to have_received(:read_body)
    end

    it "accepts a declared length equal to the limit" do
      response["content-length"] = "4"
      allow(response).to receive(:read_body).and_yield("data")

      body, redirect = described_class.send(:read_response, response, 4)

      expect(body&.read).to eq("data")
      expect(redirect).to be_nil
    end

    it "rejects an oversized declared length before reading the body" do
      response["content-length"] = "5"
      allow(response).to receive(:read_body).and_yield("data")

      expect(described_class.send(:read_response, response, 4)).to be_nil
      expect(response).not_to have_received(:read_body)
    end

    it "joins streamed chunks that reach the limit without a declared length" do
      allow(response).to receive(:read_body).and_yield("ab").and_yield("cd")

      body, = described_class.send(:read_response, response, 4)

      expect(body&.read).to eq("abcd")
    end

    it "preserves the content type and exposes its MIME type" do
      response["content-type"] = "image/png; x=y"
      allow(response).to receive(:read_body).and_yield("data")

      body, = described_class.send(:read_response, response, 4)

      expect(body).to have_attributes(content_type: "image/png; x=y", mime_type: "image/png")
    end
  end
end
