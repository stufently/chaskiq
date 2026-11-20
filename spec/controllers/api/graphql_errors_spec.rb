# frozen_string_literal: true

require "rails_helper"

RSpec.describe "GraphQL error handling", type: :request do
  let(:app_record) { FactoryBot.create(:app) }

  describe "M182: rescue StandardError vs Exception" do
    it "rescues StandardError and returns a response" do
      allow(ChaskiqSchema).to receive(:execute).and_raise(ArgumentError, "test error")
      post "/api/graphql", params: { query: "{ app { key } }" },
                           headers: { "HTTP_APP" => app_record.key, "Content-Type" => "application/json" }
      expect(response).to have_http_status(:ok).or have_http_status(:internal_server_error)
    end

    it "propagates non-StandardError when rescue clause is StandardError" do
      fatal_class = Class.new(Exception) do
        def self.name
          "TestFatalError"
        end
      end
      stub_const("TestFatalError", fatal_class)
      allow(ChaskiqSchema).to receive(:execute).and_raise(fatal_class, "fatal")

      expect {
        post "/api/graphql", params: { query: "{ app { key } }" },
                             headers: { "HTTP_APP" => app_record.key, "Content-Type" => "application/json" }
      }.to raise_error(fatal_class)
    end
  end
end
