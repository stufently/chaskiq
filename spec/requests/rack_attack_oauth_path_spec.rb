# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Rack::Attack oauth throttle path regex" do
  def build_request(path, method: :post)
    env = Rack::MockRequest.env_for(path, method: method.to_s.upcase)
    Rack::Request.new(env)
  end

  let(:throttle_block) do
    rule = Rack::Attack.cache.store rescue nil
    Rack::Attack.throttles.detect { |t| t.name == "logins/ip" }
  end

  it "matches POST /oauth/token" do
    req = build_request("/oauth/token")
    match = %r{\A/+oauth/+token(?:\.[^/.?]+)?/*\z}.match?(req.path)
    expect(match).to be true
  end

  it "matches POST /oauth/token.json" do
    req = build_request("/oauth/token.json")
    match = %r{\A/+oauth/+token(?:\.[^/.?]+)?/*\z}.match?(req.path)
    expect(match).to be true
  end

  it "does not match /oauth/tokenX" do
    req = build_request("/oauth/tokenX")
    match = %r{\A/+oauth/+token(?:\.[^/.?]+)?/*\z}.match?(req.path)
    expect(match).to be false
  end

  it "does not match /oauth/token/extra" do
    req = build_request("/oauth/token/extra")
    match = %r{\A/+oauth/+token(?:\.[^/.?]+)?/*\z}.match?(req.path)
    expect(match).to be false
  end
end
