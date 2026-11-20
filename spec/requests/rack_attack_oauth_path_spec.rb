# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Rack::Attack oauth throttle path matching" do
  let(:throttle) do
    Rack::Attack.throttles.find do |t|
      t.respond_to?(:name) ? t.name == "logins/ip" : t[0] == "logins/ip"
    end
  end

  def throttle_discriminator(path, method: "POST")
    env = Rack::MockRequest.env_for(path, method: method)
    req = Rack::Request.new(env)
    block = throttle.respond_to?(:block) ? throttle.block : throttle[1]
    block.call(req)
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
