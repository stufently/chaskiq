# frozen_string_literal: true

require "rails_helper"

RSpec.describe MessageApis::Calendly::Presenter do
  describe ".valid_url?" do
    it "returns host for valid url" do
      expect(described_class.valid_url?("https://calendly.com/x")).to eq("calendly.com")
    end

    it "returns false for invalid url" do
      expect(described_class.valid_url?("https://exa mple.com")).to be false
    end
  end

  describe ".sheet_hook" do
    it "returns fixed hash" do
      expect(described_class.sheet_hook({})).to eq({ a: 11_111 })
    end
  end

  describe ".initialize_hook" do
    it "returns definitions with invitation text" do
      params = { ctx: { values: { url: "https://calendly.com/test", invitation_text: "Book" } } }
      result = described_class.initialize_hook(params)
      first_def = result[:definitions].first
      expect(first_def[:type]).to eq("text")
      expect(first_def[:text]).to eq("Book")
    end
  end
end
