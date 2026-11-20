# frozen_string_literal: true

require "rails_helper"

RSpec.describe SubdomainOrDomain do
  def request_for(host)
    ActionDispatch::Request.new(Rack::MockRequest.env_for("http://#{host}/"))
  end

  it "matches a non-app subdomain" do
    expect(described_class.matches?(request_for("help.example.com"))).to be(true)
  end

  it "rejects each APP_SUBDOMAINS entry as a subdomain" do
    APP_SUBDOMAINS.each do |sub|
      host = "#{sub}.example.com"
      expect(described_class.matches?(request_for(host))).to be(false)
    end
  end

  it "returns nil for a bare domain with no subdomains" do
    expect(described_class.matches?(request_for("example.com"))).to be_nil
  end

  it "matches a multi-segment subdomain not in APP_SUBDOMAINS" do
    expect(described_class.matches?(request_for("www.help.example.com"))).to be(true)
  end

  it "rejects a multi-segment subdomain when the joined value is in APP_SUBDOMAINS" do
    stub_const("APP_SUBDOMAINS", ["www.help"])
    expect(described_class.matches?(request_for("www.help.example.com"))).to be(false)
  end
end
