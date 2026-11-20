# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscribable do
  describe "#payment_attribute" do
    it "returns the stripe value when paddle_subscription_plan_id is absent" do
      app = App.new(
        name: "Stripe App",
        domain_url: "http://example.com",
        stripe_subscription_status: "active",
        paddle_subscription_status: "trialing"
      )
      expect(app.payment_attribute("subscription_status")).to eq("active")
    end

    it "returns the paddle value when paddle_subscription_plan_id is present" do
      app = App.new(
        name: "Paddle App",
        domain_url: "http://example.com",
        stripe_subscription_status: "active",
        paddle_subscription_status: "trialing",
        paddle_subscription_plan_id: "123"
      )
      expect(app.payment_attribute("subscription_status")).to eq("trialing")
    end
  end
end
