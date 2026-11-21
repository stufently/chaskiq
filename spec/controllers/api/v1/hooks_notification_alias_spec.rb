# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::HooksController do
  let(:controller) { described_class.new }

  describe "#is_notification_message?" do
    it "returns true for Notification type" do
      controller.instance_variable_set(:@request_body, { "Type" => "Notification" })
      expect(controller.send(:is_notification_message?)).to eq(true)
    end

    it "returns false for SubscriptionConfirmation type" do
      controller.instance_variable_set(:@request_body, { "Type" => "SubscriptionConfirmation" })
      expect(controller.send(:is_notification_message?)).to eq(false)
    end

    it "returns false for empty body" do
      controller.instance_variable_set(:@request_body, {})
      expect(controller.send(:is_notification_message?)).to eq(false)
    end

    it "is a private method" do
      expect(described_class.private_method_defined?(:is_notification_message?)).to eq(true)
    end

    it "is not a public method" do
      expect(described_class.public_method_defined?(:is_notification_message?)).to eq(false)
    end
  end

  describe "renamed" do
    describe "#notification_message?" do
      it "returns true for Notification type" do
        controller.instance_variable_set(:@request_body, { "Type" => "Notification" })
        expect(controller.send(:notification_message?)).to eq(true)
      end

      it "returns false for SubscriptionConfirmation type" do
        controller.instance_variable_set(:@request_body, { "Type" => "SubscriptionConfirmation" })
        expect(controller.send(:notification_message?)).to eq(false)
      end

      it "returns false for empty body" do
        controller.instance_variable_set(:@request_body, {})
        expect(controller.send(:notification_message?)).to eq(false)
      end

      it "is a private method" do
        expect(described_class.private_method_defined?(:notification_message?)).to eq(true)
      end

      it "is a private method" do
        expect(described_class.private_method_defined?(:notification_message?)).to eq(true)
      end
    end
  end
end
