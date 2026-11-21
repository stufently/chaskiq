# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscribable do
  it "returns the missing subscription status for an app that uses Paddle" do
    app = App.new(
      paddle_subscription_plan_id: "123",
      paddle_subscription_status: nil,
      stripe_subscription_status: "active"
    )

    expect(app.payment_attribute("subscription_status")).to be_nil
  end
end
