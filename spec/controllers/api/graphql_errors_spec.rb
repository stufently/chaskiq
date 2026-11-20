# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::GraphqlController, type: :controller do
  describe "error handling" do
    it "rescues StandardError subclasses and renders a response" do
      request.headers["HTTP_APP"] = "nonexistent"
      allow(ChaskiqSchema).to receive(:execute).and_raise(ArgumentError, "test error")

      post :execute, params: { query: "{ app { key } }" }, as: :json
      expect(response).to have_http_status(:unprocessable_entity).or have_http_status(:ok).or have_http_status(:internal_server_error)
    end

    it "does not rescue non-StandardError exceptions" do
      non_standard = Class.new(Exception)
      allow(ChaskiqSchema).to receive(:execute).and_raise(non_standard)

      request.headers["HTTP_APP"] = "nonexistent"
      expect {
        post :execute, params: { query: "{ app { key } }" }, as: :json
      }.to raise_error(non_standard)
    end
  end
end
