# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dante::Utils do
  describe ".extract_plain_text" do
    it "separates text nodes with a space" do
      nodes = [
        { "type" => "text", "text" => "hello" },
        { "type" => "text", "text" => "world" }
      ]
      expect(described_class.extract_plain_text(nodes)).to eq("hello world")
    end

    it "walks nested node content" do
      nodes = [
        {
          "type" => "paragraph",
          "content" => [
            { "type" => "text", "text" => "inner" }
          ]
        }
      ]
      expect(described_class.extract_plain_text(nodes)).to include("inner")
    end
  end

  describe ".get_blocks" do
    it "returns the content array from serialized content" do
      content = [{ "type" => "text", "text" => "hi" }]
      serialized = { content: content }.to_json
      expect(described_class.get_blocks(serialized)).to eq(content)
    end
  end

  describe ".extract_plain_text method existence" do
    it "responds to extract_plain_text" do
      expect(described_class).to respond_to(:extract_plain_text)
    end
  end
end
