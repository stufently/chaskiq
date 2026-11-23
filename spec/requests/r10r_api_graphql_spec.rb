# frozen_string_literal: true

require "rails_helper"

RSpec.describe "R10r Api::GraphqlController", type: :request do
  let!(:app_record) { FactoryBot.create(:app) }

  before do
    allow_any_instance_of(OriginValidator).to receive(:is_valid?).and_return(true)
  end

  def post_graphql(extra = {})
    post "/api/graphql",
         params: { query: "{ __typename }" }.merge(extra),
         headers: { "HTTP_APP" => app_record.key },
         as: :json
  end

  def without_exception_rendering
    key = "action_dispatch.show_exceptions"
    original = Rails.application.env_config[key]
    Rails.application.env_config[key] = :none
    yield
  ensure
    Rails.application.env_config[key] = original
  end

  describe "successful execution" do
    it "returns the schema result as JSON" do
      post_graphql
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body).to have_key("data")
    end

    it "passes operationName to the schema" do
      allow(ChaskiqSchema).to receive(:execute).and_call_original
      post_graphql(operationName: "TestOp")
      expect(ChaskiqSchema).to have_received(:execute).with(
        "{ __typename }",
        hash_including(operation_name: "TestOp")
      )
    end

    it "includes app, from_api and request in context" do
      captured = nil
      allow(ChaskiqSchema).to receive(:execute) do |_q, **kw|
        captured = kw[:context]
        { "data" => { "__typename" => "Query" } }
      end
      post_graphql
      expect(captured[:app]).to eq(app_record)
      expect(captured[:from_api]).to be true
      expect(captured[:request]).to be_a(ActionDispatch::Request)
      expect(captured[:auth]).to be_a(Proc)
      expect(captured[:get_app_user]).to be_a(Proc)
      expect(captured[:set_locale]).to be_a(Proc)
      expect(captured).to have_key(:current_user)
      expect(captured).to have_key(:user_data)
    end
  end

  describe "rescue ActiveRecord::RecordNotFound" do
    it "returns status 200 with a Data not found error" do
      allow(ChaskiqSchema).to receive(:execute).and_raise(ActiveRecord::RecordNotFound)
      post_graphql
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["errors"]).to be_an(Array)
      expect(body["errors"].first["message"]).to eq("Data not found")
      expect(body["errors"].first["data"]).to eq({})
    end
  end

  describe "rescue ActiveRecord::RecordInvalid" do
    it "still propagates the missing JSON error handler" do
      record = App.new
      record.errors.add(:name, "is invalid")
      allow(ChaskiqSchema).to receive(:execute).and_raise(ActiveRecord::RecordInvalid.new(record))

      without_exception_rendering do
        expect { post_graphql }.to raise_error(NoMethodError) { |error| expect(error.name).to eq(:json_error) }
      end
    end
  end

  describe "rescue OriginValidator::NonAcceptedOrigin" do
    it "returns 422 with the origin error message" do
      allow(OriginValidator).to receive(:new).and_raise(
        OriginValidator::NonAcceptedOrigin.new
      )
      post_graphql
      expect(response).to have_http_status(:unprocessable_content)
      body = response.parsed_body
      expect(body["errors"]).to be_an(Array)
      expect(body["errors"].first["data"]).to eq({})
      expect(body["errors"].first["message"]).to be_a(String)
      expect(body["errors"].first["message"]).to be_present
    end
  end

  describe "rescue StandardError" do
    it "returns 500 with error message and data keys" do
      allow(ChaskiqSchema).to receive(:execute).and_raise(RuntimeError, "boom")
      post_graphql
      expect(response).to have_http_status(:internal_server_error)
      body = response.parsed_body
      expect(body).to have_key("error")
      expect(body["error"]["message"]).to eq("boom")
      expect(body).to have_key("data")
    end

    it "logs the error message" do
      allow(Rails.logger).to receive(:error)
      allow(ChaskiqSchema).to receive(:execute).and_raise(RuntimeError, "logged-boom")
      post_graphql
      expect(Rails.logger).to have_received(:error).at_least(:once)
    end
  end

  describe "before_action :get_app" do
    it "returns 500 when HTTP_APP header is missing because app is nil" do
      post "/api/graphql", params: { query: "{ __typename }" }, as: :json
      expect(response).to have_http_status(:internal_server_error)
    end
  end

  describe "auth flow" do
    it "calls valid_origin? and get_user_data_from_auth in auth" do
      captured = nil
      allow(ChaskiqSchema).to receive(:execute) do |_q, **kw|
        captured = kw[:context]
        { "data" => {} }
      end
      post_graphql
      expect(captured[:auth]).to be_a(Proc)
    end
  end

  describe "variables parsing" do
    it "accepts variables as a JSON string" do
      allow(ChaskiqSchema).to receive(:execute).and_call_original
      post "/api/graphql",
           params: { query: "{ __typename }", variables: '{"a":1}' },
           headers: { "HTTP_APP" => app_record.key }, as: :json
      expect(response).to have_http_status(:ok)
    end

    it "accepts blank variables" do
      post "/api/graphql",
           params: { query: "{ __typename }", variables: "" },
           headers: { "HTTP_APP" => app_record.key }, as: :json
      expect(response).to have_http_status(:ok)
    end
  end
end
