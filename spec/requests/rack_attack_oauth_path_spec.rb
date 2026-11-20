# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Rack::Attack oauth throttle path matching" do
  let(:throttle_entry) do
    Rack::Attack.throttles.find do |t|
      name = t.is_a?(Array) ? t[0] : t.name
      name == "logins/ip"
    end
  end

  let(:throttle_block) do
    throttle_entry.is_a?(Array) ? throttle_entry[1] : throttle_entry.block
  end

  def throttle_discriminator(path, method: "POST")
    env = Rack::MockRequest.env_for(path, method: method)
    req = Rack::Request.new(env)
    throttle_block.call(req)
  end

  it "matches POST /oauth/token" do
    expect(throttle_discriminator("/oauth/token")).to be_truthy
  end

  it "matches POST /oauth/token.json" do
    expect(throttle_discriminator("/oauth/token.json")).to be_truthy
  end

  it "does not match POST /oauth/tokenX" do
    expect(throttle_discriminator("/oauth/tokenX")).to be_nil
  end

  it "does not match POST /oauth/token/extra" do
    expect(throttle_discriminator("/oauth/token/extra")).to be_nil
  end
end
