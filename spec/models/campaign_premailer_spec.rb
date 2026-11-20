# frozen_string_literal: true

require "rails_helper"
require "webmock"

RSpec.describe Campaign do
  include WebMock::API

  subject(:campaign) { described_class.new }

  let(:host) { "http://premailer.example.com:3000" }
  let(:url) { URI.parse("#{host}/apps/sample/premailer/1") }

  around do |example|
    WebMock.enable!
    example.run
  ensure
    WebMock.reset!
    WebMock.disable!
  end

  before do
    allow(Chaskiq::Config).to receive(:get).and_call_original
    allow(Chaskiq::Config).to receive(:get).with("HOST").and_return(host)
    allow(MessageApis::SafeDownload).to receive(:resolve).with(url.host).and_return(["10.0.0.10"])
  end

  it "inlines CSS and makes Active Storage images absolute on its private host" do
    storage_path = "/rails/active_storage/blobs/logo.png"
    external_image = "https://cdn.example.com/logo.png"
    html = <<~HTML
      <html>
        <head><meta charset="utf-8"><style>.greeting { color: red; }</style></head>
        <body>
          <p class="greeting">Привет!</p>
          <img src="#{storage_path}">
          <img src="#{external_image}">
        </body>
      </html>
    HTML
    stub_request(:get, url.to_s).to_return(body: html, headers: { "Content-Type" => "text/html; charset=UTF-8" })

    rendered = Nokogiri::HTML(campaign.clean_inline_css(url))
    greeting = rendered.at_css("p.greeting")

    expect(greeting["style"]).to match(/(?:\A|;)\s*color:\s*red\s*(?:;|\z)/)
    expect(greeting.text).to eq("Привет!")
    expect(rendered.css("img").pluck("src")).to eq(["#{host}#{storage_path}", external_image])
  end

  it "follows redirects within its own origin" do
    target_url = "#{host}/apps/sample/premailer/preview"
    stub_request(:get, url.to_s).to_return(status: 302, headers: { "Location" => target_url })
    target = stub_request(:get, target_url).to_return(body: "<p>Preview content</p>")

    expect(campaign.clean_inline_css(url)).to include("Preview content")
    assert_requested(target, times: 1)
  end

  it "raises when the premailer responds with an HTTP error" do
    stub_request(:get, url.to_s).to_return(status: 500)

    expect { campaign.clean_inline_css(url) }.to raise_error(StandardError)
  end
end
