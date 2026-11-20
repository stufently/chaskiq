# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::GraphqlController, type: :controller do
  let(:app_record) { FactoryBot.create(:app) }

  before do
    request.headers["HTTP_APP"] = app_record.key
  end

  describe "M182: rescue StandardError vs Exception" do
    it "rescues StandardError and renders a response" do
      allow(ChaskiqSchema).to receive(:execute).and_raise(ArgumentError, "test error")
      post :execute, params: { query: "{ app { key } }" }, as: :json
      expect(response).to have_http_status(:ok).or have_http_status(:internal_server_error)
    end

    it "does not handle non-StandardError in the controller rescue clause" do
      fatal_class = Class.new(Exception)
      stub_const("TestFatalError", fatal_class)
      allow(ChaskiqSchema).to receive(:execute).and_raise(fatal_class, "fatal_unique_marker")

      # With `rescue StandardError` (original): exception propagates, Rails renders
      #   a generic error page — the body does NOT contain our JSON error structure.
      # With `rescue Exception` (mutant): handle_error_message renders JSON with
      #   {"error":{"message":"fatal_unique_marker",...}} — the body DOES contain it.
      post :execute, params: { query: "{ app { key } }" }, as: :json
      expect(response.body).not_to include("fatal_unique_marker")
    end
  end
end
