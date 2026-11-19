# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rack::Request do
  it "uses X-Forwarded-For and ignores the Forwarded header" do
    env = Rack::MockRequest.env_for(
      "/",
      "REMOTE_ADDR" => "10.0.0.1",
      "HTTP_X_FORWARDED_FOR" => "198.51.100.7",
      "HTTP_FORWARDED" => "for=1.2.3.4"
    )

    expect(described_class.new(env).ip).to eq("198.51.100.7")
  end

  it "prefers X-Forwarded-Scheme when determining the scheme" do
    env = Rack::MockRequest.env_for(
      "/",
      "HTTP_X_FORWARDED_SCHEME" => "https",
      "HTTP_X_FORWARDED_PROTO" => "http",
      "HTTP_FORWARDED" => "proto=http"
    )

    expect(described_class.new(env).scheme).to eq("https")
  end

  it "uses the first forwarded protocol and host in proxy chains" do
    env = Rack::MockRequest.env_for(
      "/",
      "HTTP_X_FORWARDED_PROTO" => "https, http",
      "HTTP_X_FORWARDED_HOST" => "public.example, internal"
    )
    request = described_class.new(env)

    expect(request.scheme).to eq("https")
    expect(request.host).to eq("public.example")
  end

  it "falls back to the forwarded protocol for a chained X-Forwarded-Scheme" do
    env = Rack::MockRequest.env_for(
      "/",
      "HTTP_X_FORWARDED_SCHEME" => "http, http",
      "HTTP_X_FORWARDED_PROTO" => "https"
    )

    expect(described_class.new(env).scheme).to eq("https")
  end
end
