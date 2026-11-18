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
end
