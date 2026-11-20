# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Redis initializer" do
  describe "Redis.exists_returns_integer" do
    it "is set to true" do
      expect(Redis.exists_returns_integer).to be true
    end
  end

  describe "ConnectionPool settings" do
    let(:pool) { Redis::Objects.redis }

    it "has size 5" do
      inner = pool.instance_variable_get(:@pool)
      expect(inner.size).to eq(5)
    end

    it "has timeout 5" do
      inner = pool.instance_variable_get(:@pool)
      expect(inner.instance_variable_get(:@timeout)).to eq(5)
    end

    it "timeout is not 0" do
      inner = pool.instance_variable_get(:@pool)
      expect(inner.instance_variable_get(:@timeout)).not_to eq(0)
    end
  end

  describe "REDIS_URL fallback" do
    it "defaults to db 1" do
      expect(REDIS_URL).to end_with("/1")
    end
  end
end
