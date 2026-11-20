# frozen_string_literal: true

require "rails_helper"
require "webmock"

RSpec.describe FetchLinkCardService do
  include WebMock::API

  subject(:service) { described_class.new }

  let(:url) { "https://article.example.com/story" }

  around do |example|
    WebMock.enable!
    example.run
  ensure
    WebMock.reset!
    WebMock.disable!
  end

  before do
    allow(MessageApis::SafeDownload).to receive(:resolve).with("article.example.com").and_return(["93.184.216.34"])
    provider = instance_double(OEmbed::Provider)
    allow(OEmbed::Providers).to receive(:find).with(url).and_return(provider)
    allow(provider).to receive(:get).with(url).and_raise(OEmbed::NotFound)
    stub_request(:get, url).to_return(body: html, headers: { "Content-Type" => "text/html" })
  end

  context "with both property and name metadata" do
    let(:html) do
      <<~HTML
        <meta name="og:title" content="Named title">
        <meta property="og:title" content="Open Graph title">
      HTML
    end

    it "prefers property metadata" do
      expect(service.call(url).title).to eq("Open Graph title")
    end
  end

  context "with a standard description" do
    let(:html) { '<title>Story</title><meta name="description" content="Story description">' }

    it "uses the named description when the property is absent" do
      expect(service.call(url).description).to eq("Story description")
    end
  end

  context "with a title property that has no content attribute" do
    let(:html) { '<meta property="og:title"><title>Document title</title>' }

    it "falls back to the document title" do
      expect(service.call(url).title).to eq("Document title")
    end
  end

  context "with an empty named title" do
    let(:html) { '<meta name="og:title" content=""><title>Document title</title>' }

    it "uses the document title" do
      expect(service.call(url)).to have_attributes(title: "Document title")
    end
  end

  context "with a blank title property and a populated named title" do
    let(:html) do
      <<~HTML
        <meta property="og:title" content=" ">
        <meta name="og:title" content="Named title">
      HTML
    end

    it "uses the named title" do
      expect(service.call(url)).to have_attributes(title: "Named title")
    end
  end
end
