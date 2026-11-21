# frozen_string_literal: true

require "rails_helper"

RSpec.describe "GraphQL operationName type error" do
  describe GraphqlController do
    it "returns an error when operationName is an Array" do
      post :execute, params: { query: "{ __typename }", operationName: ["x"] }
      expect(response.body).to include("no implicit conversion of Array into String")
    end
  end

  describe Api::GraphqlController do
    let!(:app) { FactoryBot.create(:app) }

    before do
      request.headers["HTTP_APP"] = app.key
    end

    it "returns an error when operationName is an Array" do
      post :execute, params: { query: "{ __typename }", operationName: ["x"] }
      expect(response.body).to include("no implicit conversion of Array into String")
    end
  end
end
