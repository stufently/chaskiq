# frozen_string_literal: true

require "rails_helper"

RSpec.describe Plan do
  subject(:plan) do
    features = [
      { name: "agents", count: 5, active: true },
      { name: "campaigns", count: "unlimited", active: false }
    ]
    described_class.new(features: features)
  end

  it "wraps the feature hashes and preserves their names and counts" do
    expected_features = [
      an_instance_of(Plan::Feature).and(have_attributes(name: "agents", count: 5)),
      an_instance_of(Plan::Feature).and(have_attributes(name: "campaigns", count: "unlimited"))
    ]
    expect(plan.features).to match(expected_features)
  end

  it "enables active features and disables inactive features" do
    expect(plan.enabled?("agents")).to be(true)
    expect(plan.enabled?("campaigns")).to be(false)
  end

  it "enables features outside the plan" do
    expect(plan.enabled?("reports")).to be(true)
  end
end
