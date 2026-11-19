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

  def expect_token_response
    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    token = Doorkeeper::AccessToken.find_by!(token: body["access_token"])
    expect(token.application).to eq(oauth_app)
    expect(token.resource_owner_id).to eq(agent.id)
    expect(token.scopes.to_s).to eq("")
    expect(token.expires_in).to eq(1.hour.to_i)
    expect(body["expires_in"]).to eq(1.hour.to_i)
    expect(body["refresh_token"]).to be_present
    expect(body["refresh_token"]).to eq(token.refresh_token)
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
