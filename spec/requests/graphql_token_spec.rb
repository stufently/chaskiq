# frozen_string_literal: true

require "rails_helper"

RSpec.describe "GraphQL access token", type: :request do
  let(:project) { FactoryBot.create(:app) }
  let(:agent) do
    project.add_agent({ email: "agent@example.com" }, role_attrs: { access_list: ["manage"], role: "admin" }).agent
  end
  let(:token) { Doorkeeper::AccessToken.create!(resource_owner_id: agent.id, expires_in: 3600) }

  def query_app
    post "/graphql",
         params: { query: "query App($key: String!) { app(key: $key) { key } }", variables: { key: project.key } },
         headers: { "Authorization" => "Bearer #{token.token}" },
         as: :json
  end

  it "accepts a valid token" do
    query_app

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("data", "app", "key")).to eq(project.key)
  end

  it "refuses a revoked token that has not expired yet" do
    token.revoke

    query_app

    expect(response).to have_http_status(:unauthorized)
  end

  it "refuses an expired token" do
    token.update_columns(created_at: 2.hours.ago)

    query_app

    expect(response).to have_http_status(:unauthorized)
  end
end
