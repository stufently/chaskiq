# frozen_string_literal: true

# Probe for fork-updates-m2: Rack::Attack must not crash on JSON bodies that are valid JSON
# but not an object, and such requests must still be counted as password-grant attempts.
# Run: bash docs/specs/fork-updates-m2-probes/rspec_gate_m2.sh --only docs/specs/fork-updates-m2-probes/m2_runtime_probe_spec.rb
require_relative "../../../spec/rails_helper"

RSpec.describe "fork-updates-m2 runtime probe", type: :request do
  around do |example|
    previous = Rack::Attack.cache.store
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    example.run
  ensure
    Rack::Attack.cache.store = previous
  end

  def raw_json_post(path, body, ip)
    post path, params: body, env: { "REMOTE_ADDR" => ip, "CONTENT_TYPE" => "application/json" }
    response.status
  end

  { "null" => "10.40.0.1", "[]" => "10.40.0.2", "[1,2]" => "10.40.0.3", "\"text\"" => "10.40.0.4",
    "42" => "10.40.0.5" }.each do |body, ip|
    it "does not raise or return 500 for JSON body #{body} on /oauth/token.json and counts it" do
      statuses = []
      expect { 20.times { statuses << raw_json_post("/oauth/token.json", body, ip) } }.not_to raise_error
      expect(statuses).not_to include(500)
      expect(statuses).not_to include(429)
      expect(raw_json_post("/oauth/token.json", body, ip)).to eq(429)
    end
  end

  it "still exempts refresh_token JSON grants" do
    ip = "10.40.0.9"
    body = { grant_type: "refresh_token", refresh_token: "x" }.to_json
    statuses = Array.new(25) { raw_json_post("/oauth/token", body, ip) }
    expect(statuses).not_to include(429)
    expect(statuses).not_to include(500)
  end
end
