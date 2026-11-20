# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Rack::Attack oauth throttle path matching" do
  let(:throttle) { Rack::Attack.throttles.detect { |t| t.name == "logins/ip" } }

  def matched_by_throttle?(path, method: "POST")
    env = Rack::MockRequest.env_for(path, method: method)
    req = Rack::Request.new(env)
    throttle&.block_verb == "throttle" && throttle&.([](req))
  rescue StandardError
    nil
  end

  it "matches POST /oauth/token" do
    env = Rack::MockRequest.env_for("/oauth/token", method: "POST")
    req = Rack::Request.new(env)
    result = throttle.call(req) if throttle
    expect(result).to be_truthy
  end

  it "matches POST /oauth/token.json" do
    env = Rack::MockRequest.env_for("/oauth/token.json", method: "POST")
    req = Rack::Request.new(env)
    result = throttle.call(req) if throttle
    expect(result).to be_truthy
  end

  it "does not match POST /oauth/tokenX" do
    env = Rack::MockRequest.env_for("/oauth/tokenX", method: "POST")
    req = Rack::Request.new(env)
    result = throttle.call(req) if throttle
    expect(result).to be_falsy
  end

  it "does not match POST /oauth/token/extra" do
    env = Rack::MockRequest.env_for("/oauth/token/extra", method: "POST")
    req = Rack::Request.new(env)
    result = throttle.call(req) if throttle
    expect(result).to be_falsy
  end
end
