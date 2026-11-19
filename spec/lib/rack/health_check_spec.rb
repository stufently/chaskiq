# frozen_string_literal: true

require "rails_helper"
require_relative "../../../lib/rack/health_check"

RSpec.describe Rack::HealthCheck do
  it "creates one Redis client before the first request" do
    allow(Redis).to receive(:new).and_call_original

    described_class.new

    expect(Redis).to have_received(:new).with(no_args).once
  end

  it "returns 200 when Redis responds" do
    status, _, body = described_class.new.call({})

    expect(status).to eq(200)
    expect(JSON.parse(body.first)).to eq("redis" => { "connected" => true })
  end

  it "returns 503 when Redis is unavailable" do
    unavailable = Redis.new(url: "redis://127.0.0.1:1/0")
    allow(Redis).to receive(:new).with(no_args).and_return(unavailable)

    status, _, body = described_class.new.call({})

    expect(status).to eq(503)
    expect(JSON.parse(body.first)).to eq("redis" => { "connected" => false })
  end
end
