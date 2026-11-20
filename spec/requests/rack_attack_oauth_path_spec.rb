# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Rack::Attack oauth throttle path matching" do
  let(:throttle) { Rack::Attack.throttles["logins/ip"] }

  def discriminator_for(path, method: "POST")
    env = Rack::MockRequest.env_for(path, method: method, input: "grant_type=password")
    env["CONTENT_TYPE"] = "application/x-www-form-urlencoded"
    env["REMOTE_ADDR"] = "1.2.3.4"
    req = Rack::Request.new(env)
    throttle.send(:discriminator_for, req)
  end

  it "matches POST /oauth/token" do
    expect(discriminator_for("/oauth/token")).to be_truthy
  end

  it "matches POST /oauth/token.json" do
    expect(discriminator_for("/oauth/token.json")).to be_truthy
  end

  it "does not match POST /oauth/tokenX" do
    expect(discriminator_for("/oauth/tokenX")).to be_nil
  end

  it "does not match POST /oauth/token/extra" do
    expect(discriminator_for("/oauth/token/extra")).to be_nil
  end
end
