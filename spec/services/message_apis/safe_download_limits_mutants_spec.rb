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

  let(:initial_url) { "https://cdn.example.com/a" }
  let(:second_url) { "https://cdn.example.com/b" }
  let(:third_url) { "https://cdn.example.com/c" }

  before do
    allow(described_class).to receive(:resolve).and_return(["93.184.216.34"])
  end

  def stub_redirect(url, destination)
    stub_request(:get, url).to_return(status: 302, headers: { "Location" => destination })
  end

  it "returns the body after exactly one redirect when the limit is one" do
    first = stub_redirect(initial_url, second_url)
    second = stub_request(:get, second_url).to_return(body: "downloaded")

    expect(described_class.fetch(initial_url, max_redirects: 1)&.read).to eq("downloaded")
    assert_requested(first, times: 1)
    assert_requested(second, times: 1)
  end

  it "requests the allowed hop and stops before exceeding the redirect limit" do
    first = stub_redirect(initial_url, second_url)
    second = stub_redirect(second_url, third_url)
    third = stub_request(:get, third_url).to_return(body: "beyond the limit")

    expect(described_class.fetch(initial_url, max_redirects: 1)).to be_nil
    assert_requested(first, times: 1)
    assert_requested(second, times: 1)
    assert_not_requested(third)
  end

  it "checks the URL policy on a redirect target before requesting it" do
    target_url = "https://other.example.com/b"
    first = stub_redirect(initial_url, target_url)
    target = stub_request(:get, target_url).to_return(body: "rejected")
    policy = ->(uri) { uri.hostname == "cdn.example.com" }

    expect(described_class.fetch(initial_url, url_allowed: policy)).to be_nil
    assert_requested(first, times: 1)
    assert_not_requested(target)
  end

  it "sends authorization only on the initial request, including for a same-host redirect" do
    headers = { "Authorization" => "Bearer test-token" }
    first = stub_request(:get, initial_url).with(headers: headers)
                                           .to_return(status: 302, headers: { "Location" => second_url })
    target = stub_request(:get, second_url).to_return(body: "downloaded")

    expect(described_class.fetch(initial_url, headers: headers)&.read).to eq("downloaded")
    assert_requested(first, times: 1)
    assert_requested(target, times: 1)
    assert_not_requested(:get, second_url) { |request| request.headers.key?("Authorization") }
  end

  it "resolves a relative redirect location against the current URL" do
    stub_redirect(initial_url, "/b")
    target = stub_request(:get, second_url).to_return(body: "downloaded")

    expect(described_class.fetch(initial_url)&.read).to eq("downloaded")
    assert_requested(target, times: 1)
  end

  it "follows three redirects with the default limit" do
    final_url = "https://cdn.example.com/d"
    stub_redirect(initial_url, second_url)
    stub_redirect(second_url, third_url)
    stub_redirect(third_url, final_url)
    final = stub_request(:get, final_url).to_return(body: "downloaded")

    expect(described_class.fetch(initial_url)&.read).to eq("downloaded")
    assert_requested(final, times: 1)
  end

  it "returns the response body for a direct download with the default deadline" do
    download = stub_request(:get, initial_url).to_return(body: "downloaded")

    expect(described_class.fetch(initial_url)&.read).to eq("downloaded")
    assert_requested(download, times: 1)
  end
end
