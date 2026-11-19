# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Rack::Attack login throttling", type: :request do
  around do |example|
    previous_store = Rack::Attack.cache.store
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    example.run
  ensure
    Rack::Attack.cache.store = previous_store
  end

  def post_token(path, ip, grant_type: "password", json: false)
    body = { grant_type: grant_type, email: "test@example.com", password: "wrong",
             refresh_token: "fake" }
    if json
      post path, params: body, env: { "REMOTE_ADDR" => ip }, as: :json
    else
      post path, params: body, env: { "REMOTE_ADDR" => ip }
    end
    response.status
  end

  it "allows up to 20 password-grant requests per hour from one IP" do
    20.times do
      status = post_token("/oauth/token.json", "10.0.0.1", json: true)
      expect(status).not_to eq(429)
    end
  end

  it "returns 429 on the 21st password-grant request from the same IP" do
    20.times { post_token("/oauth/token.json", "10.0.0.2", json: true) }
    expect(post_token("/oauth/token.json", "10.0.0.2", json: true)).to eq(429)
  end

  it "counts an invalid forwarded address against the remote address limit" do
    request_token = lambda do |address|
      post "/oauth/token", params: { grant_type: "password" }, as: :json,
                           env: { "REMOTE_ADDR" => address, "HTTP_X_FORWARDED_FOR" => "invalid/address" }
      response.status
    end

    20.times { expect(request_token.call("10.0.0.8")).not_to eq(429) }
    expect(request_token.call("10.0.0.8")).to eq(429)
    expect(request_token.call("10.0.0.9")).not_to eq(429)
  end

  it "preserves a non-rewindable JSON body for Doorkeeper" do
    agent = Agent.create!(email: "stream@example.com", password: "test-password")
    client = Doorkeeper::Application.create!(name: "Stream test", redirect_uri: "", confidential: false)
    payload = { grant_type: "password", email: agent.email, password: "test-password", client_id: client.uid }.to_json
    stream = Rack::Lint::Wrapper::InputWrapper.new(StringIO.new(payload))

    result = Rack::MockRequest.new(Rails.application).post(
      "/oauth/token", input: stream, "CONTENT_TYPE" => "application/json",
      "CONTENT_LENGTH" => payload.bytesize.to_s, "REMOTE_ADDR" => "10.0.0.10"
    )

    expect(result.status).to eq(200)
    expect(JSON.parse(result.body)).to include("access_token" => be_present)
  end

  it "throttles form posts to /oauth/token the same way" do
    20.times { post_token("/oauth/token", "10.0.0.3") }
    expect(post_token("/oauth/token", "10.0.0.3")).to eq(429)
  end

  it "does not throttle a different IP" do
    20.times { post_token("/oauth/token.json", "10.0.0.4", json: true) }
    expect(post_token("/oauth/token.json", "10.0.0.5", json: true)).not_to eq(429)
  end

  it "does not count refresh_token grants" do
    25.times do
      status = post_token("/oauth/token", "10.0.0.6", grant_type: "refresh_token", json: true)
      expect(status).not_to eq(429)
    end
  end

  it "does not throttle other POST endpoints" do
    25.times do
      status = post_token("/oauth/revoke", "10.0.0.7")
      expect(status).not_to eq(429)
    end
  end
  { "null" => "10.0.1.1", "[]" => "10.0.1.2" }.each do |body, ip|
    it "counts JSON body #{body} toward the login limit without returning 500" do
      statuses = []
      expect do
        20.times do
          post "/oauth/token.json", params: body,
                                   env: { "REMOTE_ADDR" => ip, "CONTENT_TYPE" => "application/json" }
          statuses << response.status
        end
      end.not_to raise_error
      expect(statuses).not_to include(500, 429)

      post "/oauth/token.json", params: body,
                               env: { "REMOTE_ADDR" => ip, "CONTENT_TYPE" => "application/json" }
      expect(response.status).to eq(429)
    end
  end

  include ActiveSupport::Testing::TimeHelpers

  %w[xml html].each do |format|
    it "counts requests with the #{format} route format" do
      path = "/oauth/token.#{format}"
      20.times { expect(post_token(path, "10.0.2.1")).not_to eq(429) }
      expect(post_token(path, "10.0.2.1")).to eq(429)
    end
  end

  [false, true].each do |json|
    it "uses the query grant type with a #{json ? 'JSON' : 'form'} body" do
      request_token = lambda do
        post_token("/oauth/token?grant_type=password", "10.0.2.2", grant_type: "refresh_token", json: json)
      end
      20.times { expect(request_token.call).not_to eq(429) }
      expect(request_token.call).to eq(429)
    end
  end

  it "counts malformed JSON even when Rails rejects the body" do
    request_token = lambda do
      post "/oauth/token", params: "{bad", env: { "CONTENT_TYPE" => "application/json", "REMOTE_ADDR" => "10.0.2.3" }
      response.status
    rescue ActionDispatch::Http::Parameters::ParseError
      :invalid_parameters
    end
    expect(Array.new(20) { request_token.call }).not_to include(429, 500)
    expect(request_token.call).to eq(429)
  end

  it "keeps the limit for one hour" do
    start = Time.zone.at((Time.now.to_i / 3600 + 1) * 3600 + 1)
    travel_to(start) { 20.times { expect(post_token("/oauth/token", "10.0.2.4")).not_to eq(429) } }
    travel_to(start + 3590) { expect(post_token("/oauth/token", "10.0.2.4")).to eq(429) }
    travel_to(start + 3610) { expect(post_token("/oauth/token", "10.0.2.4")).not_to eq(429) }
  end
end
