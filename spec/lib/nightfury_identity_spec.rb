# frozen_string_literal: true

require "rails_helper"

class MutbTestIdentity < Nightfury::Identity::Base
  tag :region
  tag :plan
  metric :visits, :count_time_series, step: :minute
end

class ModuleA
  class FooIdentity < Nightfury::Identity::Base
    metric :counter, :count_time_series, step: :minute
  end
end

RSpec.describe Nightfury::Identity::Base do
  let(:nf_redis) { Nightfury.redis }
  let(:id) { SecureRandom.hex(6) }

  after do
    nf_redis.keys("mutb_test_identity.#{id}*").each { |k| nf_redis.del(k) }
    nf_redis.keys("foo_identity.*").each { |k| nf_redis.del(k) }
  end

  describe "tags in key_prefix" do
    it "includes tag values in the key prefix" do
      identity = MutbTestIdentity.new(id, tags: { region: "us" })
      expect(identity.key_prefix).to include("region.us")
    end
  end

  describe "tag sorting" do
    it "sorts tags alphabetically regardless of insertion order" do
      identity = MutbTestIdentity.new(id, tags: { region: "us", plan: "pro" })
      prefix = identity.key_prefix
      expect(prefix).to end_with(":plan.pro:region.us")
    end
  end

  describe "nil tags" do
    it "returns nil tag_ids when tags are nil" do
      identity = MutbTestIdentity.new(id)
      expect(identity.key_prefix).to eq("mutb_test_identity.#{id}")
    end
  end

  describe ".name" do
    it "demodulizes nested module names" do
      expect(ModuleA::FooIdentity.name).to eq("foo_identity")
    end
  end

  describe "key_prefix format" do
    it "uses dot separator between name and id" do
      identity = MutbTestIdentity.new(id)
      expect(identity.key_prefix).to eq("mutb_test_identity.#{id}")
    end
  end
end
