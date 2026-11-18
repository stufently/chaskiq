# frozen_string_literal: true

# Probe for fork-updates-m3 (Rack::Attack login throttle bypasses).
# Run: bash docs/specs/fork-updates-m3-probes/rspec_gate_m3.sh --only docs/specs/fork-updates-m3-probes/m3_attack_probe_spec.rb
# Every password-grant POST that Rails routes to the token endpoint must be counted
# (20 per hour per IP); a request is exempt only when the grant_type that Rails/doorkeeper
# would see is refresh_token. Rails merges request_parameters.merge(query_parameters), so
# the query string wins over the body.
require "rails_helper"

RSpec.describe "fork-updates-m3 probe: Rack::Attack login throttle", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  around do |example|
    previous_store = Rack::Attack.cache.store
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    example.run
  ensure
    Rack::Attack.cache.store = previous_store
  end

  let(:creds) { { email: "probe@example.com", password: "wrong" } }

  def form_post(path, ip, params)
    post path, params: params, env: { "REMOTE_ADDR" => ip }
    response.status
  end

  def raw_post(path, ip, body, content_type)
    post path, params: body, env: { "REMOTE_ADDR" => ip, "CONTENT_TYPE" => content_type }
    response.status
  rescue ActionDispatch::Http::Parameters::ParseError
    # raised by Rails after Rack::Attack let the request through (malformed JSON)
    :rails_parse_error
  end

  def expect_counted(times: 20)
    statuses = Array.new(times) { yield }
    expect(statuses).not_to include(429, 500)
    expect(yield).to eq(429)
  end

  {
    "/oauth/token.xml" => "10.3.0.1",
    "/oauth/token.html" => "10.3.0.2",
    "/oauth/token.anything" => "10.3.0.3",
    "/oauth/token/" => "10.3.0.4",
    "//oauth/token" => "10.3.0.5",
    "/oauth/token.json/" => "10.3.0.6"
  }.each do |path, ip|
    it "counts password grants posted to #{path}" do
      expect_counted { form_post(path, ip, creds.merge(grant_type: "password")) }
    end
  end

  it "shares one counter per IP across all token path variants and body formats" do
    ip = "10.3.0.9"
    statuses = []
    7.times { statuses << form_post("/oauth/token.xml", ip, creds.merge(grant_type: "password")) }
    7.times { statuses << form_post("/oauth/token", ip, creds.merge(grant_type: "password")) }
    6.times do
      statuses << raw_post("/oauth/token.json", ip, creds.merge(grant_type: "password").to_json, "application/json")
    end
    expect(statuses).not_to include(429, 500)
    expect(form_post("/oauth/token/", ip, creds.merge(grant_type: "password"))).to eq(429)
  end

  it "counts a password grant hidden behind a refresh_token form body (query wins)" do
    expect_counted do
      form_post("/oauth/token?grant_type=password", "10.3.1.1", creds.merge(grant_type: "refresh_token"))
    end
  end

  it "counts a password grant hidden behind a refresh_token JSON body (query wins)" do
    body = creds.merge(grant_type: "refresh_token").to_json
    expect_counted { raw_post("/oauth/token.json?grant_type=password", "10.3.1.2", body, "application/json") }
  end

  it "counts a password grant in the query with no grant_type in the body" do
    expect_counted { form_post("/oauth/token?grant_type=password", "10.3.1.3", creds) }
  end

  it "counts malformed JSON bodies and never leaks a JSON parser error from the middleware" do
    statuses = []
    expect do
      20.times { statuses << raw_post("/oauth/token.json", "10.3.2.1", "{bad", "application/json") }
    end.not_to raise_error
    expect(statuses).not_to include(429, 500)
    expect(raw_post("/oauth/token.json", "10.3.2.1", "{bad", "application/json")).to eq(429)
  end

  it "still exempts a plain refresh_token grant (form body)" do
    statuses = Array.new(25) { form_post("/oauth/token", "10.3.3.1", grant_type: "refresh_token", refresh_token: "x") }
    expect(statuses).not_to include(429)
  end

  it "still exempts a plain refresh_token grant (JSON body)" do
    body = { grant_type: "refresh_token", refresh_token: "x" }.to_json
    statuses = Array.new(25) { raw_post("/oauth/token.json", "10.3.3.2", body, "application/json") }
    expect(statuses).not_to include(429)
  end

  it "keeps the window at one hour" do
    start = Time.zone.at((Time.now.to_i / 3600 + 1) * 3600 + 1)
    travel_to(start) do
      20.times { form_post("/oauth/token", "10.3.4.1", creds.merge(grant_type: "password")) }
    end
    travel_to(start + 3590) do
      expect(form_post("/oauth/token", "10.3.4.1", creds.merge(grant_type: "password"))).to eq(429)
    end
    travel_to(start + 3610) do
      expect(form_post("/oauth/token", "10.3.4.1", creds.merge(grant_type: "password"))).not_to eq(429)
    end
  end
end
