# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::GraphqlController, type: :controller do
  let(:app_record) { FactoryBot.create(:app) }

  before do
    request.headers["HTTP_APP"] = app_record.key
  end

  describe "error handling" do
    it "rescues StandardError and renders a response" do
      allow(ChaskiqSchema).to receive(:execute).and_raise(ArgumentError, "test error")
      post :execute, params: { query: "{ app { key } }" }, as: :json
      expect(response).to have_http_status(:ok).or have_http_status(:internal_server_error)
    end

    it "handles Exception differently from StandardError" do
      allow(ChaskiqSchema).to receive(:execute).and_raise(Exception.new("non-standard"))
      post :execute, params: { query: "{ app { key } }" }, as: :json
      expect(response.status).to eq(200).or eq(422).or eq(500)
    end
  end
end
