# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Rack request compatibility" do
  let(:client) { Rack::MockRequest.new(Rails.application) }

  it "redirects Sidekiq Web to the first host and protocol in proxy chains" do
    allow(Chaskiq::Config).to receive(:get).and_call_original
    allow(Chaskiq::Config).to receive(:get).with("ADMIN_EMAIL").and_return("admin@example.com")
    allow(Chaskiq::Config).to receive(:get).with("ADMIN_PASSWORD").and_return("test-password")
    authorization = ActionController::HttpAuthentication::Basic.encode_credentials("admin@example.com", "test-password")

    response = client.get(
      "/sidekiq/dashboard/stats",
      "HTTP_AUTHORIZATION" => authorization,
      "HTTP_X_FORWARDED_PROTO" => "https, http",
      "HTTP_X_FORWARDED_HOST" => "public.example, internal"
    )

    expect(response.status).to eq(302)
    expect(response["location"]).to eq("https://public.example/sidekiq/stats")
  end

  it "acknowledges SNS confirmation JSON without a content type" do
    url = "https://sns.us-east-1.amazonaws.com/confirmation"
    allow(MessageApis::SafeDownload).to receive(:fetch).with(url, max_redirects: 0)

    response = client.post("/api/v1/hooks", input: { "SubscribeURL" => url }.to_json,
                                            "HTTP_X_AMZ_SNS_MESSAGE_TYPE" => "SubscriptionConfirmation")

    expect(response.status).to eq(200)
    expect(MessageApis::SafeDownload).to have_received(:fetch).with(url, max_redirects: 0)
  end

  it "returns 400 for a multipart boundary rejected before Rails dispatch" do
    boundary = "b" * 71
    response = client.post("/api/v1/hooks", input: "--#{boundary}--\r\n",
                                            "CONTENT_TYPE" => "multipart/form-data; boundary=#{boundary}", lint: true)

    expect(response.status).to eq(400)
  end

  it "serves static files with a Rack-compatible cache-control header" do
    response = client.get("/robots.txt", lint: true)

    expect(response.status).to eq(200)
    expect(response["cache-control"]).to eq("public, max-age=3600")
  end
end
