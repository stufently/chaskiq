# frozen_string_literal: true

require "rails_helper"

RSpec.describe "GraphQL controller error handling" do
  it "rescues StandardError not Exception" do
    source = Rails.root.join("app/controllers/api/graphql_controller.rb").read
    expect(source).to match(/rescue\s+StandardError/)
    expect(source).not_to match(/rescue\s+Exception\b/)
  end
end
