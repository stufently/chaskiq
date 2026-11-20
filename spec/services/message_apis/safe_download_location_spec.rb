# frozen_string_literal: true

require "rails_helper"

RSpec.describe MessageApis::SafeDownload do
  describe ".read_response" do
    def make_redirect(location)
      response = Net::HTTPFound.new("1.1", "302", "Found")
      response["location"] = location if location
      response
    end

    it "returns [nil, location] for redirect with valid location" do
      response = make_redirect("/next")
      result = described_class.send(:read_response, response, 10)
      expect(result).to eq([nil, "/next"])
    end

    it "returns [nil, location] for redirect with whitespace-only location" do
      response = make_redirect("  ")
      result = described_class.send(:read_response, response, 10)
      expect(result).to eq([nil, "  "])
    end

    it "returns nil for redirect with empty location" do
      response = make_redirect("")
      result = described_class.send(:read_response, response, 10)
      expect(result).to be_nil
    end

    it "returns nil for redirect without location header" do
      response = make_redirect(nil)
      result = described_class.send(:read_response, response, 10)
      expect(result).to be_nil
    end
  end
end
