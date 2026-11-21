# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::GraphqlController, type: :controller do
  it "returns the origin validator error with status 422" do
    app = FactoryBot.create(:app)
    request.headers.merge!("HTTP_APP" => app.key, "HTTP_ORIGIN" => "http://evil.example")

    post :execute, params: { query: "{ __typename }" }

    expect(response.status).to eq(422)
    expect(response.parsed_body.dig("errors", 0, "message")).to start_with("not accepted origin")
  end
end
