# frozen_string_literal: true

require "rails_helper"
require "webmock"

RSpec.describe FetchLinkCardService do
  subject { FetchLinkCardService.new }

  context "with HTTP responses" do
    include WebMock::API

    around do |example|
      WebMock.enable!
      example.run
    ensure
      WebMock.reset!
      WebMock.disable!
    end

    it "makes no request for a private page" do
      url = "https://internal.example.com/card"
      allow(MessageApis::SafeDownload).to receive(:resolve).with("internal.example.com").and_return(["10.0.0.1"])
      outbound = stub_request(:any, url)

      expect(subject.call(url)).to be_nil
      assert_not_requested(outbound)
    end

    it "builds an opengraph card from one GET without requesting its private image" do
      url = "https://site.example.com/article"
      image_url = "https://internal.example.com/thumbnail.png"
      html = <<~HTML
        <html><head>
          <meta property="og:title" content="Article title">
          <meta property="og:image" content="#{image_url}">
        </head></html>
      HTML
      allow(MessageApis::SafeDownload).to receive(:resolve).with("site.example.com").and_return(["93.184.216.34"])
      allow(MessageApis::SafeDownload).to receive(:resolve).with("internal.example.com").and_return(["10.0.0.1"])
      allow(OEmbed::Providers).to receive(:get).with(url).and_raise(OEmbed::NotFound)
      page = stub_request(:get, url).to_return(body: html, headers: { "Content-Type" => "text/html; charset=UTF-8" })
      image = stub_request(:get, image_url)

      card = subject.call(url)

      expect(card).to be_persisted
      expect(card.title).to eq("Article title")
      expect(card.image).not_to be_attached
      assert_requested(page, times: 1)
      assert_not_requested(image)
    end

    it "uses the HTML charset declared in the response header" do
      url = "https://site.example.com/article"
      allow(MessageApis::SafeDownload).to receive(:resolve).with("site.example.com").and_return(["93.184.216.34"])
      allow(OEmbed::Providers).to receive(:get).with(url).and_raise(OEmbed::NotFound)
      stub_request(:get, url).to_return(
        body: "<title>Привет</title>".encode("Windows-1251").b,
        headers: { "Content-Type" => 'text/html; Charset="Windows-1251"' }
      )

      expect(subject.call(url).title).to eq("Привет")
    end

    it "uses opengraph for unregistered providers without following oEmbed discovery" do
      url = "https://site.example.com/post"
      endpoint = "https://internal.example.com/oembed"
      html = <<~HTML
        <html><head>
          <link rel="alternate" type="application/json+oembed" href="#{endpoint}">
          <meta property="og:title" content="Open Graph title">
        </head></html>
      HTML
      allow(MessageApis::SafeDownload).to receive(:resolve).with("site.example.com").and_return(["93.184.216.34"])
      allow(MessageApis::SafeDownload).to receive(:resolve).with("internal.example.com").and_return(["10.0.0.1"])
      page = stub_request(:get, url).to_return(body: html, headers: { "Content-Type" => "text/html" })
      discovery = stub_request(:get, /\A#{Regexp.escape(endpoint)}(?:\?|\z)/).to_return(
        body: { type: "link", title: "Discovered title", width: 0, height: 0 }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

      expect(subject.call(url).title).to eq("Open Graph title")
      assert_requested(page, times: 1)
      assert_not_requested(discovery)
    end

    it "keeps previews from a registered oEmbed provider" do
      url = "https://www.youtube.com/watch?v=example"
      allow(MessageApis::SafeDownload).to receive(:resolve).with("www.youtube.com").and_return(["93.184.216.34"])
      stub_request(:get, url).to_return(body: "<title>Fallback</title>", headers: { "Content-Type" => "text/html" })
      provider = stub_request(:get, "https://www.youtube.com/oembed/")
                 .with(query: { "scheme" => "https", "format" => "json", "url" => url })
                 .to_return(body: { type: "video", title: "Video title", width: 640, height: 360 }.to_json)

      expect(subject.call(url).title).to eq("Video title")
      assert_requested(provider, times: 1)
    end
  end

  #   before do
  #     stub_request(:head, 'http://example.xn--fiqs8s/').to_return(status: 200, headers: { 'Content-Type' => 'text/html' })
  #     stub_request(:get, 'http://example.xn--fiqs8s/').to_return(request_fixture('idn.txt'))
  #     stub_request(:head, 'https://github.com/qbi/WannaCry').to_return(status: 404)
  #     subject.call(status)
  #   end
  #
  #   context 'card preview' do
  #     context do
  #       let(:status) { "http://example.xn--fiqs8s/" }
  #
  #       it 'works with IDN URLs' do
  #         expect(PreviewCard.all.size).to be == 1
  #         expect(a_request(:get, 'http://example.xn--fiqs8s/')).to have_been_made.at_least_once
  #       end
  #     end
  #   end

  context "live" do
    it "request twitter user" do
      # fetch = FetchLinkCardService.new.call("https://twitter.com/michelson")
      # fetch = subject.call("https://twitter.com/Hugo_Gutierrez_/status/1010591929338343424")
      # fetch = subject.call("http://vadb.org/people/miguel-michelson-martinez")
    end
  end
end
