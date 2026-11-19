# frozen_string_literal: true

require "rails_helper"
require "webmock"

RSpec.describe MessageApis::SafeDownload do
  include WebMock::API

  around do |example|
    WebMock.enable!
    example.run
  ensure
    WebMock.reset!
    WebMock.disable!
  end

  let(:url) { "https://media.telnyx.com/original" }

  before do
    allow(described_class).to receive(:resolve).and_return(["93.184.216.34"])
  end

  shared_examples "an authorization-free redirect" do |location|
    it "sends caller headers only before a redirect to #{location}" do
      required_headers = { "Authorization" => "Bearer test-key", "Accept-Encoding" => "identity" }
      first = stub_request(:get, url).with(headers: required_headers)
                                     .to_return(status: 302, headers: { "Location" => location })
      redirected = stub_request(:get, URI.join(url, location)).with { |request| !request.headers.key?("Authorization") }
      redirected.to_return(body: "downloaded")
      headers = { "Authorization" => "Bearer test-key", "accept-encoding" => "gzip" }

      expect(described_class.fetch(url, headers: headers)&.read).to eq("downloaded")
      assert_requested(first, times: 1)
      assert_requested(redirected, times: 1)
    end
  end

  include_examples "an authorization-free redirect", "https://files.example.com/final"
  include_examples "an authorization-free redirect", "/final"

  it "checks the URL policy before resolving the first hop" do
    policy = ->(uri) { uri.host == "other.telnyx.com" }
    download = stub_request(:get, url).to_return(body: "rejected")

    expect(described_class.fetch(url, url_allowed: policy)).to be_nil
    expect(described_class).not_to have_received(:resolve)
    assert_not_requested(download)
  end

  it "allows a private own host by default and rejects it when the exception is disabled" do
    allow(Chaskiq::Config).to receive(:get).and_call_original
    allow(Chaskiq::Config).to receive(:get).with("HOST").and_return("https://media.telnyx.com")
    allow(described_class).to receive(:resolve).with("media.telnyx.com").and_return(["10.0.0.5"])
    download = stub_request(:get, url).to_return(body: "own host")

    expect(described_class.fetch(url)&.read).to eq("own host")
    expect(described_class.fetch(url, allow_own_host: false)).to be_nil
    assert_requested(download, times: 1)
  end

  it "disables the private own host exception after a redirect as well" do
    own_url = "https://own.example.com/final"
    allow(Chaskiq::Config).to receive(:get).and_call_original
    allow(Chaskiq::Config).to receive(:get).with("HOST").and_return("https://own.example.com")
    allow(described_class).to receive(:resolve).with("own.example.com").and_return(["10.0.0.5"])
    first = stub_request(:get, url).to_return(status: 302, headers: { "Location" => own_url })
    final = stub_request(:get, own_url).to_return(body: "own host")

    expect(described_class.fetch(url, allow_own_host: false)).to be_nil
    assert_requested(first, times: 1)
    assert_not_requested(final)
  end

  it "sends no extra headers by default (base-green)" do
    download = stub_request(:get, url).with(headers: { "Accept-Encoding" => "identity" }) do |request|
      !request.headers.key?("Authorization")
    end
    download.to_return(body: "downloaded")

    expect(described_class.fetch(url)&.read).to eq("downloaded")
    assert_requested(download, times: 1)
  end
end
