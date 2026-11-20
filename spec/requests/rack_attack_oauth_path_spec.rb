# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Rack::Attack oauth throttle path matching" do
  let(:throttle) { Rack::Attack.throttles["logins/ip"] }

  def throttle_matches?(path, method: "POST")
    env = Rack::MockRequest.env_for(path, method: method, input: "grant_type=password")
    env["CONTENT_TYPE"] = "application/x-www-form-urlencoded"
    req = Rack::Request.new(env)
    throttle.matched_by?(req)
  end

  it "matches POST /oauth/token" do
    expect(throttle_matches?("/oauth/token")).to be true
  end

  it "matches POST /oauth/token.json" do
    expect(throttle_matches?("/oauth/token.json")).to be true
  end

  it "does not match POST /oauth/tokenX" do
    expect(throttle_matches?("/oauth/tokenX")).to be false
  end

  it "does not match POST /oauth/token/extra" do
    expect(throttle_matches?("/oauth/token/extra")).to be false
  end
end
