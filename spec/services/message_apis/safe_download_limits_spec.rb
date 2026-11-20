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

  let(:public_ip) { "93.184.216.34" }

  it "returns nil when redirects exceed max_redirects" do
    url1 = "https://cdn.example.com/a"
    url2 = "https://cdn.example.com/b"
    url3 = "https://cdn.example.com/c"

    allow(described_class).to receive(:resolve).with("cdn.example.com").and_return([public_ip])
    stub_request(:get, url1).to_return(status: 302, headers: { "Location" => url2 })
    stub_request(:get, url2).to_return(status: 302, headers: { "Location" => url3 })
    stub_request(:get, url3).to_return(status: 302, headers: { "Location" => "https://cdn.example.com/d" })

    expect(described_class.fetch(url1, max_redirects: 1)).to be_nil
  end

  it "returns nil and makes no request when url_allowed rejects" do
    url = "https://cdn.example.com/image.png"
    allow(described_class).to receive(:resolve).with("cdn.example.com").and_return([public_ip])
    download = stub_request(:get, url).to_return(body: "image")

    result = described_class.fetch(url, url_allowed: ->(_uri) { false })
    expect(result).to be_nil
    assert_not_requested(download)
  end
end
