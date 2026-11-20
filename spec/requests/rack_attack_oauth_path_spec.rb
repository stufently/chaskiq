# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Rack::Attack oauth throttle path matching" do
  let(:throttle) do
    Rack::Attack.throttles.detect { |t| t.respond_to?(:name) ? t.name == "logins/ip" : t[0] == "logins/ip" }
  end

  def throttle_matches?(path, method: "POST")
    env = Rack::MockRequest.env_for(path, method: method)
    req = Rack::Request.new(env)
    if throttle.respond_to?(:call)
      throttle.call(req)
    elsif throttle.is_a?(Array)
      throttle[1].call(req)
    end
  rescue StandardError
    nil
  end

  it "matches POST /oauth/token" do
    expect(throttle_matches?("/oauth/token")).to be_truthy
  end

  it "matches POST /oauth/token.json" do
    expect(throttle_matches?("/oauth/token.json")).to be_truthy
  end

  it "does not match POST /oauth/tokenX" do
    expect(throttle_matches?("/oauth/tokenX")).to be_falsy
  end

  it "does not match POST /oauth/token/extra" do
    expect(throttle_matches?("/oauth/token/extra")).to be_falsy
  end
end
