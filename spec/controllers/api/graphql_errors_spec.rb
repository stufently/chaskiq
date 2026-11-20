# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::GraphqlController, type: :controller do
  let(:app_record) { FactoryBot.create(:app) }

  before do
    request.headers["HTTP_APP"] = app_record.key
  end

  describe "M182: rescue StandardError vs Exception" do
    it "rescues StandardError and returns JSON error response" do
      allow(ChaskiqSchema).to receive(:execute).and_raise(ArgumentError, "test error")
      post :execute, params: { query: "{ app { key } }" }, as: :json
      expect(response).to have_http_status(:internal_server_error)
      expect(response.parsed_body).to have_key("error")
    end

    it "does not produce controller-rendered JSON for non-StandardError" do
      fatal_class = Class.new(Exception) # rubocop:disable Lint/InheritException
      stub_const("TestFatalError", fatal_class)
      allow(ChaskiqSchema).to receive(:execute).and_raise(fatal_class, "fatal_test")

      post :execute, params: { query: "{ app { key } }" }, as: :json
      json = response.parsed_body
      if json.is_a?(Hash) && json.dig("error", "message") == "fatal_test"
        flunk "non-StandardError was caught by controller rescue clause (mutant: rescue Exception)"
      end
      expect(response.status).to eq(500)
    end
  end
end
