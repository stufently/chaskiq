# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Agent sign in", type: :request do
  let!(:oauth_app) do
    Doorkeeper::Application.create!(name: "authapp", redirect_uri: "http://localhost:5002",
                                    confidential: false)
  end
  let!(:agent) { Agent.create!(email: "agent@example.com", password: "secret123") }

  def sign_in_params(password: "secret123")
    { agent: { email: agent.email, password: password } }
  end

  def issued_token
    Doorkeeper::AccessToken.find_by!(token: response.parsed_body["access_token"])
  end

  def expect_token_record(token)
    expect(token).to have_attributes(application_id: oauth_app.id, resource_owner_id: agent.id,
                                     expires_in: 1.hour.to_i, refresh_token: be_present)
    expect(token.scopes.to_s).to eq("")
  end

  def expect_token_response
    expect(response).to have_http_status(:ok)
    token = issued_token
    expect_token_record(token)
    expect(response.parsed_body).to include("expires_in" => 1.hour.to_i,
                                            "refresh_token" => token.refresh_token)
  end

  it "returns an access token for a JSON sign in" do
    post "/agents/sign_in", params: sign_in_params, as: :json
    expect_token_response
  end

  it "returns an access token for a form sign in" do
    post "/agents/sign_in", params: sign_in_params
    expect_token_response
  end

  it "rejects a wrong password without issuing a token" do
    post "/agents/sign_in", params: sign_in_params(password: "wrong"), as: :json
    expect(response).to have_http_status(:found)
    expect(Doorkeeper::AccessToken.count).to eq(0)
  end
end
