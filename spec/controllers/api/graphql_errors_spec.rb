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
      json = JSON.parse(response.body)
      expect(json).to have_key("error")
    end

    it "does not produce controller-rendered JSON for non-StandardError" do
      fatal_class = Class.new(Exception)
      stub_const("TestFatalError", fatal_class)
      allow(ChaskiqSchema).to receive(:execute).and_raise(fatal_class, "fatal_test")

      # With `rescue StandardError` (original): non-StandardError propagates.
      #   Rails test middleware renders an HTML error page (not JSON with "error" key).
      # With `rescue Exception` (mutant): handle_error_message renders JSON
      #   {"error":{"message":"fatal_test",...},"data":{}}.
      post :execute, params: { query: "{ app { key } }" }, as: :json
      content_type = response.content_type.to_s
      json = JSON.parse(response.body) rescue nil
      if json && json.key?("error") && json["error"].is_a?(Hash) && json["error"]["message"] == "fatal_test"
        flunk "non-StandardError was caught by controller rescue clause (mutant: rescue Exception)"
      end
      # Original: either HTML error page or generic JSON without our structured error
      expect(response.status).to eq(500)
    end
  end
end
