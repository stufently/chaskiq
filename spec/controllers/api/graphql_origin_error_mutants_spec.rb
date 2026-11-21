# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::GraphqlController, type: :controller do
  describe "origin error mutant-killing" do
    it "X22: returns the exact OriginValidator error message" do
      app = FactoryBot.create(:app)
      request.headers.merge!("HTTP_APP" => app.key, "HTTP_ORIGIN" => "http://evil.example")

      post :execute, params: { query: "{ __typename }" }

      expected = OriginValidator::NonAcceptedOrigin.new.message
      expect(response.parsed_body.dig("errors", 0, "message")).to eq(expected)
    end

    it "X23: returns an empty hash for the error data" do
      app = FactoryBot.create(:app)
      request.headers.merge!("HTTP_APP" => app.key, "HTTP_ORIGIN" => "http://evil.example")

      post :execute, params: { query: "{ __typename }" }

      expect(response.parsed_body.dig("errors", 0, "data")).to eq({})
    end
  end
end
