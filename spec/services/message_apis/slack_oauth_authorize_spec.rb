# frozen_string_literal: true

require "rails_helper"

RSpec.describe MessageApis::Slack::Api, "#oauth_authorize" do
  let(:api) do
    described_class.new(config: { "api_key" => "client-1", "api_secret" => "secret-1" })
  end

  let(:package) { double(oauth_url: "https://app.example.com/oauth/slack") }

  let(:url) { api.oauth_authorize(nil, package) }
  let(:uri) { URI.parse(url) }
  let(:query) { Rack::Utils.parse_query(uri.query) }

  it "builds the correct authorize URL" do
    expect(uri.scheme).to eq("https")
    expect(uri.host).to eq("slack.com")
    expect(uri.path).to eq("/oauth/v2/authorize")
  end

  it "includes all expected query parameters" do
    expected_scope = "files:read,channels:history,channels:join,chat:write," \
                     "channels:read,channels:manage,chat:write.customize," \
                     "users:read,users:read.email"
    expected = {
      "client_id" => "client-1",
      "response_type" => "code",
      "redirect_uri" => "https://app.example.com/oauth/slack",
      "user_scope" => "channels:history,channels:write,channels:read",
      "scope" => expected_scope
    }
    expect(query).to eq(expected)
  end
end
