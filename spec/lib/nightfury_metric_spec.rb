# frozen_string_literal: true

require "rails_helper"

RSpec.describe Nightfury::Metric::Base do
  describe "#redis_key" do
    it "returns just the name when prefix is blank" do
      metric = described_class.new(:x, redis_key_prefix: "")
      expect(metric.redis_key).to eq("x")
    end

    it "includes the prefix when present" do
      metric = described_class.new(:x, redis_key_prefix: "p")
      expect(metric.redis_key).to eq("p:x")
    end

    it "uses blank? not nil? for prefix check" do
      metric = described_class.new(:x, redis_key_prefix: "")
      expect(metric.redis_key).not_to start_with(":")
    end
  end
end
