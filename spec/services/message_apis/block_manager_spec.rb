require "rails_helper"

RSpec.describe MessageApis::BlockManager do
  describe ".deliver_attachments" do
    let(:audio) { { "type" => "AudioRecorderBlock", "attrs" => { "url" => "https://cdn.example.com/voice.ogg" } } }
    let(:image) { { "type" => "ImageBlock", "attrs" => { "url" => "https://cdn.example.com/image.png" } } }
    let(:file) { { "type" => "FileBlock", "attrs" => { "url" => "https://cdn.example.com/file.pdf" } } }
    let(:sent_texts) { [] }
    let(:send_text) { ->(text) { sent_texts << text } }
    let(:success) { double("successful response", success?: true) }
    let(:failure) { double("failed response", success?: false) }

    it "sends a separate caption after a captionless success and returns the media response" do
      captions = []
      result = described_class.deliver_attachments(
        [audio], "voice", send_text: send_text, captionless: %w[AudioRecorderBlock]
      ) do |_type, _url, caption|
        captions << caption
        success
      end

      expect(captions).to eq([nil])
      expect(sent_texts).to eq(["voice"])
      expect(result).to equal(success)
    end

    it "keeps the caption until a caption-capable attachment succeeds after a captionless success" do
      captions = []
      result = described_class.deliver_attachments(
        [audio, image, file, image], "files", send_text: send_text, captionless: %w[AudioRecorderBlock]
      ) do |type, _url, caption|
        captions << caption
        type == "ImageBlock" ? failure : success
      end

      expect(captions).to eq([nil, "files", "files", nil])
      expect(sent_texts).to be_empty
      expect(result).to equal(success)
    end

    it "calls on_success for every successful request before the next one" do
      text_response = double("successful text", success?: true)
      calls = []
      send_caption = lambda do |_caption|
        calls << :text
        text_response
      end
      result = described_class.deliver_attachments(
        [audio, audio], "voice",
        send_text: send_caption, captionless: %w[AudioRecorderBlock],
        on_success: ->(response) { calls << response }
      ) do
        calls << :audio
        success
      end

      expect(calls).to eq([:audio, success, :audio, success, :text, text_response])
      expect(result).to equal(success)
    end

    it "calls on_failure after sending the remaining attachments" do
      calls = []
      replies = [success, failure, success]
      result = described_class.deliver_attachments(
        [image, file, audio], "files", send_text: send_text, on_failure: ->(response) { calls << response }
      ) do |type, _url, _caption|
        calls << type
        replies.shift
      end

      expect(calls).to eq(["ImageBlock", "FileBlock", "AudioRecorderBlock", failure])
      expect(result).to equal(success)
    end

    it "excludes the returned failure from on_failure" do
      hidden_failures = []
      last_failure = double("last failed response", success?: false)
      replies = [failure, last_failure]
      result = described_class.deliver_attachments(
        [image, file], "", send_text: send_text, on_failure: ->(response) { hidden_failures << response }
      ) { replies.shift }

      expect(hidden_failures).to eq([failure])
      expect(result).to equal(last_failure)
    end

    it "consumes the caption when already_sent replays eligible media" do
      captions = []
      unusable = image.merge("attrs" => { "url" => "" })
      result = described_class.deliver_attachments(
        [unusable, image, file], "files", send_text: send_text, already_sent: 1
      ) do |type, _url, caption|
        captions << [type, caption]
        success
      end

      expect(captions).to eq([["FileBlock", nil]])
      expect(sent_texts).to be_empty
      expect(result).to equal(success)
    end

    it "counts a separate caption in already_sent" do
      result = described_class.deliver_attachments(
        [audio], "voice", send_text: send_text, captionless: %w[AudioRecorderBlock], already_sent: 2
      ) { raise "already delivered audio" }

      expect(sent_texts).to be_empty
      expect(result).to be_nil
    end
  end

  describe ".get_blocks" do
    it "reads Dante nodes from the legacy blocks wrapper" do
      nodes = [{ "type" => "text", "text" => "hello" }]
      blocks = described_class.get_blocks({ blocks: [nil, *nodes, 42] }.to_json)

      expect(blocks).to eq(nodes)
      expect(described_class.plain_text(blocks)).to eq("hello")
    end

    it "skips non-Hash entries in the legacy blocks wrapper without raising" do
      node = { "type" => "paragraph", "content" => [{ "type" => "text", "text" => "kept" }] }
      blocks = nil

      expect { blocks = described_class.get_blocks({ blocks: [nil, "str", node] }.to_json) }.not_to raise_error
      expect(blocks).to eq([node])
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

    it "keeps the Draft.js media text as a caption and preserves its URL" do
      url = "/uploads/attachment"

      %w[image file recorded-audio recorded-video video].each do |type|
        content = { blocks: [{ key: "m1", type: type, text: "#{type} caption", data: { url: url } }] }
        blocks = described_class.get_blocks(content.to_json)

        expect(described_class.block_data(blocks.first)).to include("url" => url)
        expect(described_class.plain_text(blocks)).to eq("#{type} caption")
      end
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

    it "uses a Dante media caption when the message has no other text" do
      image = { "type" => "ImageBlock", "attrs" => { "caption" => "  Photo caption  " } }
      text = { "type" => "text", "text" => "Message text" }

      expect(described_class.plain_text([image])).to eq("Photo caption")
      expect(described_class.plain_text([image, text])).to eq("Message text")
    end
  end

  describe ".absolute_url" do
    it "encodes a space in a relative URL without re-encoding existing escapes" do
      allow(Chaskiq::Config).to receive(:get).with("HOST").and_return("https://chat.example.com/base/")

      expect(described_class.absolute_url("/uploads/my file%20(1).png"))
        .to eq("https://chat.example.com/base/uploads/my%20file%20(1).png")
    end

    it "rejects URLs with a non-HTTP scheme instead of treating them as relative paths" do
      allow(Chaskiq::Config).to receive(:get).with("HOST").and_return("https://chat.example.com")

      expect(described_class.absolute_url("javascript:alert(1)")).to be_nil
      expect(described_class.absolute_url("ftp://example.com/f")).to be_nil
    end

    it "rejects an HTTP URL without a host" do
      allow(Chaskiq::Config).to receive(:get).with("HOST").and_return("https://chat.example.com")

      expect(described_class.absolute_url("http:///x")).to be_nil
    end

    it "uses the host from a protocol-relative URL" do
      allow(Chaskiq::Config).to receive(:get).with("HOST").and_return("https://chat.example.com/base/")

      expect(described_class.absolute_url("//cdn.example.com/my file.png"))
        .to eq("https://cdn.example.com/my%20file.png")
    end

    it "percent-encodes unicode letters with ASCII case-folding equivalents" do
      allow(Chaskiq::Config).to receive(:get).with("HOST").and_return("https://chat.example.com")

      expect(described_class.absolute_url("HTTPS://cdn.example.com/\u212A\u017F.png"))
        .to eq("HTTPS://cdn.example.com/%E2%84%AA%C5%BF.png")
      expect(described_class.absolute_url("\u212A:file.png"))
        .to eq("https://chat.example.com/%E2%84%AA:file.png")
    end
  end
end
