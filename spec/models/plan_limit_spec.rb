# frozen_string_literal: true

require "rails_helper"

RSpec.describe Plan do
  subject(:plan) do
    features = [
      { name: "agents", count: 5 },
      { name: "campaigns", count: "unlimited" }
    ]
    described_class.new(features: features)
  end

  it "allows usage below the limit" do
    expect(plan.limit_reached?("agents", 4)).to be(false)
  end

  it "reaches the limit at the threshold" do
    expect(plan.limit_reached?("agents", 5)).to be(true)
  end

  it "reports usage above the limit as having reached it" do
    expect(plan.limit_reached?("agents", 6)).to be(true)
  end

  it "allows usage for an unlimited feature" do
    expect(plan.limit_reached?("campaigns", 100)).to be(false)
  end

  it "allows usage for a feature outside the plan" do
    expect(plan.limit_reached?("reports", 100)).to be(false)
  end
end
