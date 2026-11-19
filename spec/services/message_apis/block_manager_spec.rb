require "rails_helper"

RSpec.describe MessageApis::BlockManager do
  describe ".get_blocks" do
    it "reads Dante nodes from the legacy blocks wrapper" do
      nodes = [{ "type" => "text", "text" => "hello" }]
      blocks = described_class.get_blocks({ blocks: [nil, *nodes, 42] }.to_json)

      expect(blocks).to eq(nodes)
      expect(described_class.plain_text(blocks)).to eq("hello")
    end

    it "converts Draft.js text and preserves the image URL" do
      url = "/uploads/image.png"
      content = { blocks: [
        { key: "p1", type: "unstyled", text: "hello" },
        { key: "i1", type: "image", text: "", data: { url: url } }
      ] }
      blocks = described_class.get_blocks(content.to_json)

      expect(described_class.plain_text(blocks)).to eq("hello")
      expect(blocks.first).to eq("type" => "paragraph", "content" => [{ "type" => "text", "text" => "hello" }])
      expect(blocks.last).to include("type" => "ImageBlock")
      expect(described_class.block_data(blocks.last)).to eq("url" => url)
    end
  end

  describe ".plain_text" do
    it "separates paragraph blocks with a newline" do
      blocks = %w[a b].map do |text|
        { "type" => "paragraph", "content" => [{ "type" => "text", "text" => text }] }
      end

      expect(described_class.plain_text(blocks)).to eq("a\nb")
    end

    it "keeps consecutive hard breaks between inline text nodes" do
      blocks = [{ "type" => "paragraph", "content" => [
        { "type" => "text", "text" => "foo" }, { "type" => "hardBreak" }, { "type" => "hard_break" },
        { "type" => "text", "text" => "bar" }
      ] }]

      expect(described_class.plain_text(blocks)).to eq("foo\n\nbar")
    end
  end

  describe ".absolute_url" do
    it "encodes a space in a relative URL without re-encoding existing escapes" do
      allow(Chaskiq::Config).to receive(:get).with("HOST").and_return("https://chat.example.com/base/")

      expect(described_class.absolute_url("/uploads/my file%20(1).png"))
        .to eq("https://chat.example.com/base/uploads/my%20file%20(1).png")
    end
  end
end
