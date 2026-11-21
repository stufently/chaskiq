# frozen_string_literal: true

require "rails_helper"

RSpec.describe AppPackage do
  describe "#is_external?" do
    it "returns false for existing plugin without author" do
      expect(described_class.new(name: "Slack").is_external?).to eq(false)
    end

    it "returns true for non-existing plugin without author" do
      expect(described_class.new(name: "NoSuchPluginR7c").is_external?).to eq(true)
    end

    it "returns true when author is present" do
      expect(described_class.new(name: "Slack", author: Agent.new).is_external?).to eq(true)
    end

    it "returns false when plugin is a new record" do
      expect(described_class.new(name: "NoSuchPluginR7c", plugin: Plugin.new).is_external?).to eq(false)
    end
  end

  describe "renamed" do
    describe "#external?" do
      it "returns false for existing plugin without author" do
        expect(described_class.new(name: "Slack").external?).to eq(false)
      end

      it "returns true for non-existing plugin without author" do
        expect(described_class.new(name: "NoSuchPluginR7c").external?).to eq(true)
      end

      it "returns true when author is present" do
        expect(described_class.new(name: "Slack", author: Agent.new).external?).to eq(true)
      end

      it "returns false when plugin is a new record" do
        expect(described_class.new(name: "NoSuchPluginR7c", plugin: Plugin.new).external?).to eq(false)
      end
    end
  end
end
