# frozen_string_literal: true

require "rails_helper"

RSpec.describe "R10r GraphqlController", type: :request do
  def post_graphql(extra = {})
    post "/graphql", params: { query: "{ __typename }" }.merge(extra), as: :json
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

    it "includes current_user, request, doorkeeper_authorize and enabled_subscriptions in context" do
      captured = nil
      allow(ChaskiqSchema).to receive(:execute) do |_q, **kw|
        captured = kw[:context]
        { "data" => { "__typename" => "Query" } }
      end
      post_graphql
      expect(captured[:request]).to be_a(ActionDispatch::Request)
      expect(captured[:doorkeeper_authorize]).to be_a(Proc)
      expect(captured[:enabled_subscriptions]).to be(true).or be(false)
    end
  end

  describe "rescue OauthExeption" do
    it "returns 401 with token not valid message" do
      allow(ChaskiqSchema).to receive(:execute).and_raise(OauthExeption)
      post_graphql
      expect(response).to have_http_status(:unauthorized)
      body = response.parsed_body
      expect(body["error"]["message"]).to eq("token not valid")
      expect(body["data"]).to eq({})
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

  describe "rescue Plan::PlanError" do
    it "returns 402 with the plan error message" do
      allow(ChaskiqSchema).to receive(:execute).and_raise(
        Plan::PlanError, '{"message":"limit reached"}'
      )
      post_graphql
      expect(response).to have_http_status(:payment_required)
      body = response.parsed_body
      expect(body["error"]["message"]).to eq({ "message" => "limit reached" })
      expect(body["data"]).to eq({})
    end
  end

  describe "rescue ActionPolicy::Unauthorized" do
    it "raises a GraphQL error with the policy extensions" do
      policy = AppPolicy.new(FactoryBot.create(:app), user: Agent.new(id: -999))
      policy.apply(:show?)
      allow(ChaskiqSchema).to receive(:execute).and_raise(ActionPolicy::Unauthorized.new(policy, :show?))

      without_exception_rendering do
        expect { post_graphql }.to raise_error(GraphQL::ExecutionError) do |error|
          expect(error.extensions).to include(code: :unauthorized, fullMessages: [], details: {})
        end
      end
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
  end

  describe "rescue order" do
    it "OauthExeption is caught before StandardError" do
      allow(ChaskiqSchema).to receive(:execute).and_raise(OauthExeption, "oauth")
      post_graphql
      expect(response).to have_http_status(:unauthorized)
    end

    it "RecordNotFound is caught before StandardError" do
      allow(ChaskiqSchema).to receive(:execute).and_raise(ActiveRecord::RecordNotFound)
      post_graphql
      expect(response).to have_http_status(:ok)
    end

    it "Plan::PlanError is caught before StandardError" do
      allow(ChaskiqSchema).to receive(:execute).and_raise(
        Plan::PlanError, '{"message":"limit"}'
      )
      post_graphql
      expect(response).to have_http_status(:payment_required)
    end
  end

  describe "skip_before_action :verify_authenticity_token" do
    it "does not require CSRF token for POST" do
      post_graphql
      expect(response).to have_http_status(:ok)
    end
  end

  describe "variables parsing" do
    it "accepts variables as a JSON string" do
      allow(ChaskiqSchema).to receive(:execute).and_call_original
      post "/graphql", params: { query: "{ __typename }", variables: '{"a":1}' }, as: :json
      expect(response).to have_http_status(:ok)
    end
  end
end
