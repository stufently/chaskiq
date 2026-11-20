# frozen_string_literal: true

require "rails_helper"
require "webmock"

RSpec.describe Campaign do
  include WebMock::API

  subject(:campaign) { described_class.new }

  let(:host) { "http://premailer.example.com:3000" }
  let(:url) { URI.parse("#{host}/apps/sample/premailer/1") }
  let(:fetch_error) do
    # BASE lacks the error class. Still run the request and check how it fails there.
    defined?(Campaign::PremailerFetchError) ? Campaign::PremailerFetchError : Class.new(StandardError)
  end

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

  it "rejects a redirect to a public origin without requesting it" do
    target_url = "http://public.example.com:3000/premailer"
    allow(MessageApis::SafeDownload).to receive(:resolve).with("public.example.com").and_return(["93.184.216.34"])
    stub_request(:get, url.to_s).to_return(status: 302, headers: { "Location" => target_url })
    target = stub_request(:get, target_url).to_return(body: "<p>Other page</p>")

    expect { campaign.clean_inline_css(url) }.to raise_error(fetch_error)
    assert_not_requested(target)
  end

  it "rejects a private host outside the configured origin without requesting it" do
    private_url = URI.parse("http://other-private.example.com:3000/premailer")
    allow(MessageApis::SafeDownload).to receive(:resolve).with(private_url.host).and_return(["10.0.0.20"])
    request = stub_request(:get, private_url.to_s).to_return(body: "<p>Private page</p>")

    expect { campaign.clean_inline_css(private_url) }.to raise_error(fetch_error)
    assert_not_requested(request)
  end

  it "raises a premailer fetch error for an HTTP failure" do
    stub_request(:get, url.to_s).to_return(status: 500)

    expect { campaign.clean_inline_css(url) }.to raise_error(fetch_error)
  end
end
