# frozen_string_literal: true

require "rails_helper"

RSpec.describe FetchLinkCardService, "#attempt_oembed" do
  subject(:service) { described_class.new }

  let(:url) { "https://oembed.example.com/video/1" }
  let(:card) { PreviewCard.new(url: url) }
  let(:provider) { instance_double(OEmbed::Provider) }

  before do
    allow(OEmbed::Providers).to receive(:find).with(url).and_return(provider)
  end

  context "when all fields are present" do
    let(:response) do
      double(
        type: "video",
        title: "Test Video",
        author_name: "Author",
        author_url: "https://author.example.com",
        provider_name: "Example Provider",
        provider_url: "https://example.com",
        width: 640,
        height: 480,
        html: "<iframe></iframe>"
      )
    end

    before do
      allow(provider).to receive(:get).with(url).and_return(response)
    end

    it "returns a persisted card with correct attributes" do
      result = service.send(:attempt_oembed, card, url)
      expect(result).to be_persisted
      expect(result.type).to be_nil
      expect(result.title).to eq("Test Video")
      expect(result.author_name).to eq("Author")
      expect(result.author_url).to eq("https://author.example.com")
      expect(result.read_attribute(:provider_name)).to eq("Example Provider")
      expect(result.read_attribute(:provider_url)).to eq("https://example.com")
      expect(result.width).to eq(640)
      expect(result.height).to eq(480)
      expect(result.html).to eq("<iframe></iframe>")
      expect(result.image).not_to be_attached
    end
  end

  context "when no text fields are present" do
    let(:response) do
      double(type: "link", width: nil, height: nil)
    end

    before do
      allow(provider).to receive(:get).with(url).and_return(response)
    end

    it "stores empty strings for text fields and 0 for dimensions" do
      result = service.send(:attempt_oembed, card, url)
      expect(result).to be_persisted
      expect(result.title).to eq("")
      expect(result.author_name).to eq("")
      expect(result.author_url).to eq("")
      expect(result.read_attribute(:provider_name)).to eq("")
      expect(result.read_attribute(:provider_url)).to eq("")
      expect(result.width).to eq(0)
      expect(result.height).to eq(0)
      expect(result.html).to be_nil
    end
  end

  context "when thumbnail_url is present" do
    let(:response) do
      double(
        type: "photo",
        title: "Photo",
        author_name: "",
        author_url: "",
        provider_name: "",
        provider_url: "",
        width: 100,
        height: 100,
        thumbnail_url: "https://example.com/thumb.png"
      )
    end

    let(:uploaded_file) do
      tempfile = Tempfile.new(["thumb", ".png"])
      tempfile.write("fake png content")
      tempfile.rewind
      ActionDispatch::Http::UploadedFile.new(
        filename: "thumb.png",
        type: "image/png",
        tempfile: tempfile
      )
    end

    before do
      allow(provider).to receive(:get).with(url).and_return(response)
      allow(service).to receive(:download_image).with("https://example.com/thumb.png").and_return(uploaded_file)
    end

    it "attaches the thumbnail" do
      result = service.send(:attempt_oembed, card, url)
      expect(result).to be_persisted
      expect(result.image).to be_attached
    end
  end

  context "when download_image raises" do
    let(:response) do
      double(
        type: "photo",
        title: "Photo",
        author_name: "",
        author_url: "",
        provider_name: "",
        provider_url: "",
        width: 100,
        height: 100,
        thumbnail_url: "https://example.com/broken.png"
      )
    end

    before do
      allow(provider).to receive(:get).with(url).and_return(response)
      allow(service).to receive(:download_image).and_raise(StandardError, "download failed")
    end

    it "saves the card without an attachment" do
      result = service.send(:attempt_oembed, card, url)
      expect(result).to be_persisted
      expect(result.image).not_to be_attached
    end
  end

  context "when provider is not found" do
    before do
      allow(OEmbed::Providers).to receive(:find).with(url).and_return(nil)
    end

    it "returns nil" do
      result = service.send(:attempt_oembed, card, url)
      expect(result).to be_nil
    end
  end

  context "when OEmbed::NotFound is raised" do
    before do
      allow(provider).to receive(:get).with(url).and_raise(OEmbed::NotFound)
    end

    it "returns false and does not save the card" do
      result = service.send(:attempt_oembed, card, url)
      expect(result).to eq(false)
      expect(card).not_to be_persisted
    end
  end
end
