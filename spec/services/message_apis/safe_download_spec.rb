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

  let(:url) { "https://cdn.example.com/image.png" }
  let(:public_ip) { "93.184.216.34" }

  it "preserves the content type header and normalizes the MIME type" do
    allow(described_class).to receive(:resolve).with("cdn.example.com").and_return([public_ip])
    content_type = "Image/PNG ; charset=UTF-8"
    stub_request(:get, url).to_return(body: "image", headers: { "Content-Type" => content_type })

    body = described_class.fetch(url)

    expect(body).to be_a(StringIO)
    expect(body.read).to eq("image")
    expect(body.content_type).to eq(content_type)
    expect(body.mime_type).to eq("image/png")
  end

  it "refuses a private address even when DNS also returns a public address" do
    allow(described_class).to receive(:resolve).with("cdn.example.com").and_return([public_ip, "10.0.0.1"])
    download = stub_request(:get, url).to_return(body: "image")

    expect(described_class.fetch(url)).to be_nil
    assert_not_requested(download)
  end

  it "blocks mapped IPv4 loopback and private addresses" do
    expect(described_class.blocked_ip?("::ffff:127.0.0.1")).to be(true)
    expect(described_class.blocked_ip?("::ffff:10.0.0.1")).to be(true)
    expect(described_class.blocked_ip?("::ffff:93.184.216.34")).to be(false)
  end

  it "blocks Azure WireServer" do
    expect(described_class.blocked_ip?("168.63.129.16")).to be(true)
    expect(described_class.blocked_ip?("::ffff:168.63.129.16")).to be(true)
    expect(described_class.blocked_ip?("168.63.129.17")).to be(false)
  end

  it "blocks NAT64, 6to4, Teredo and IPv4-compatible prefixes" do
    %w[64:ff9b::1 64:ff9b:1::1 2002::1 2001::1 ::192.0.2.5].each do |address|
      expect(described_class.blocked_ip?(address)).to be(true), "expected #{address} to be blocked"
    end
  end

  it "blocks a redirect to a host that resolves to a private address" do
    internal_url = "https://internal.example.com/image.png"
    allow(described_class).to receive(:resolve).with("cdn.example.com").and_return([public_ip])
    allow(described_class).to receive(:resolve).with("internal.example.com").and_return(["10.0.0.1"])
    first_hop = stub_request(:get, url).to_return(status: 302, headers: { "Location" => internal_url })
    next_hop = stub_request(:get, internal_url).to_return(body: "image")

    expect(described_class.fetch(url)).to be_nil
    assert_requested(first_hop, times: 1)
    assert_not_requested(next_hop)
  end

  it "follows a relative redirect only within the redirect limit" do
    allow(described_class).to receive(:resolve).with("cdn.example.com").and_return([public_ip])
    stub_request(:get, url).to_return(status: 302, headers: { "Location" => "/moved.png" })
    next_hop = stub_request(:get, "https://cdn.example.com/moved.png").to_return(body: "image")

    expect(described_class.fetch(url, max_redirects: 0)).to be_nil
    assert_not_requested(next_hop)
    expect(described_class.fetch(url, max_redirects: 1).read).to eq("image")
    assert_requested(next_hop, times: 1)
  end

  it "applies one deadline across redirects and across DNS lookups" do
    allow(described_class).to receive(:resolve).with("cdn.example.com").and_return([public_ip])
    first_hop = stub_request(:get, url).to_return do
      sleep 0.12
      { status: 302, headers: { "Location" => "https://other.example.com/image.png" } }
    end
    allow(described_class).to receive(:resolve).with("other.example.com") do
      sleep 0.12
      [public_ip]
    end
    next_hop = stub_request(:get, "https://other.example.com/image.png").to_return(body: "image")

    expect(described_class.fetch(url, deadline: 0.2)).to be_nil
    assert_requested(first_hop, times: 1)
    assert_not_requested(next_hop)
  end

  it "uses a checked fallback address after a connection error" do
    fallback_ip = "8.8.8.8"
    allow(described_class).to receive(:resolve).with("cdn.example.com").and_return([public_ip, fallback_ip])
    attempted_addresses = []
    allow_any_instance_of(Net::HTTP).to receive(:ipaddr=).and_wrap_original do |set_address, address|
      attempted_addresses << address
      set_address.call(address)
    end
    download = stub_request(:get, url).to_raise(Errno::ECONNREFUSED).then.to_return(body: "image")

    expect(described_class.fetch(url)&.read).to eq("image")
    expect(attempted_addresses).to eq([public_ip, fallback_ip])
    assert_requested(download, times: 2)
  end

  it "refuses an oversized Content-Length" do
    allow(described_class).to receive(:resolve).with("cdn.example.com").and_return([public_ip])
    stub_request(:get, url).to_return(body: "image", headers: { "Content-Length" => "20" })

    expect(described_class.fetch(url, max_bytes: 5)).to be_nil
  end

  it "bounds the body by bytes when Content-Length is missing" do
    data = "\xFF\xD8\xFF".b
    allow(described_class).to receive(:resolve).with("cdn.example.com").and_return([public_ip])
    stub_request(:get, url).to_return(body: data)

    expect(described_class.fetch(url, max_bytes: 2)).to be_nil
    expect(described_class.fetch(url, max_bytes: 3).read).to eq(data)
  end

  it "rejects relative URLs, missing hosts and non-HTTP schemes" do
    [nil, "/image.png", "http:///image.png", "ftp://cdn.example.com/image.png",
     "file:///image.png", "javascript:alert(1)"].each do |address|
      expect(described_class.fetch(address)).to be_nil
    end
  end

  it "allows the configured HOST on a private address only on the same origin" do
    path = "/uploads/image.png"
    allow(Chaskiq::Config).to receive(:get).and_call_original
    allow(Chaskiq::Config).to receive(:get).with("HOST").and_return("http://CHASKIQ.example.com:3000")
    allow(described_class).to receive(:resolve).with("chaskiq.example.com").and_return(["10.0.0.1"])
    own_host = stub_request(:get, "http://chaskiq.example.com:3000#{path}").to_return(body: "image")
    other_port = stub_request(:get, "http://chaskiq.example.com:3001#{path}").to_return(body: "image")
    other_scheme = stub_request(:get, "https://chaskiq.example.com:3000#{path}").to_return(body: "image")

    expect(described_class.fetch("http://chaskiq.example.com:3000#{path}").read).to eq("image")
    expect(described_class.fetch("http://chaskiq.example.com:3001#{path}")).to be_nil
    expect(described_class.fetch("https://chaskiq.example.com:3000#{path}")).to be_nil
    assert_requested(own_host, times: 1)
    assert_not_requested(other_port)
    assert_not_requested(other_scheme)
  end
end
