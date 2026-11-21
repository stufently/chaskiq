# frozen_string_literal: true

require "rails_helper"

RSpec.describe OutgoingWebhook do
  describe "#is_enabled" do
    it "returns true when state is enabled" do
      expect(described_class.new(state: "enabled").is_enabled).to eq(true)
    end

    it "returns false when state is disabled" do
      expect(described_class.new(state: "disabled").is_enabled).to eq(false)
    end

    it "returns false when state is nil" do
      expect(described_class.new(state: nil).is_enabled).to eq(false)
    end

    it "serializes enabled as true in as_json when enabled" do
      expect(described_class.new(state: "enabled").as_json["enabled"]).to eq(true)
    end

    it "serializes enabled as false in as_json when disabled" do
      expect(described_class.new(state: "disabled").as_json["enabled"]).to eq(false)
    end
  end

  describe "renamed" do
    describe "#enabled?" do
      it "returns true when state is enabled" do
        expect(described_class.new(state: "enabled").enabled?).to eq(true)
      end

      it "returns false when state is disabled" do
        expect(described_class.new(state: "disabled").enabled?).to eq(false)
      end

      it "returns false when state is nil" do
        expect(described_class.new(state: nil).enabled?).to eq(false)
      end
    end
  end
end
