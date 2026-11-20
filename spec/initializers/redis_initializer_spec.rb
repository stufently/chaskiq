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
    it "defaults to redis://localhost:6379/1" do
      original_url = ENV["REDIS_URL"]
      original_const = defined?(::REDIS_URL) ? ::REDIS_URL : nil
      begin
        ENV.delete("REDIS_URL")
        Object.send(:remove_const, :REDIS_URL) if defined?(::REDIS_URL)
        allow(Chaskiq::Config).to receive(:fetch).with("REDIS_URL", anything).and_return(nil)
        load Rails.root.join("config/initializers/redis.rb")
        expect(REDIS_URL).to eq("redis://localhost:6379/1")
      ensure
        if original_const
          Object.send(:remove_const, :REDIS_URL) if defined?(::REDIS_URL)
          ::REDIS_URL = original_const
        end
        ENV["REDIS_URL"] = original_url
        Redis::Objects.redis = ConnectionPool.new(size: 5, timeout: 5) do
          Redis.new(url: ENV.fetch("REDIS_URL"))
        end
      end
    end
  end
end
