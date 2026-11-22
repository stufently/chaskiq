# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChaskiqSchema, "unauthorized handlers" do
  let(:error) do
    double(
      field: double(graphql_name: "secretField"),
      type: double(graphql_name: "AppType")
    )
  end

  describe ".unauthorized_field" do
    it "raises GraphQL::ExecutionError with the exact message" do
      expect { ChaskiqSchema.unauthorized_field(error) }.to raise_error(
        GraphQL::ExecutionError,
        "The field secretField on an object of type AppType was hidden due to permissions"
      )
    end
  end

  describe ".unauthorized_object" do
    it "raises GraphQL::ExecutionError with the exact message" do
      expect { ChaskiqSchema.unauthorized_object(error) }.to raise_error(
        GraphQL::ExecutionError,
        "An object of type AppType was hidden due to permissions"
      )
    end
  end
end
