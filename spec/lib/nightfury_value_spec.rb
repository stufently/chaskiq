# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Nightfury internal methods" do
  let(:redis) { Redis.new(url: ENV.fetch("REDIS_URL")) }
  let(:identity_id) { SecureRandom.hex(8) }
  let(:identity) { AppIdentity.new(identity_id) }
  let(:visits_key) { "nf-test:app_identity.#{identity_id}:visits" }
  let(:response_time_key) { "nf-test:app_identity.#{identity_id}:first_response_time" }
  let(:day) { Time.utc(2026, 11, 19) }

  after do
    redis.del(visits_key, response_time_key)
    redis.close
  end

  describe Nightfury::Metric::Value do
    let(:val) do
      Nightfury::Metric::Value.new(
        :test_val,
        redis_key_prefix: "app_identity.#{identity_id}",
        step: :day
      )
    end
    let(:val_key) { "nf-test:app_identity.#{identity_id}:test_val" }

    before { redis.del(val_key) }
    after { redis.del(val_key) }

    it "set writes the exact value to the correct redis key" do
      val.set("42")
      expect(redis.get(val_key)).to eq("42")
    end

    it "get reads from the correct redis key" do
      redis.set(val_key, "99")
      expect(val.get).to eq("99")
    end

    it "incr increments by the given step" do
      redis.set(val_key, "10")
      val.incr(5)
      expect(redis.get(val_key)).to eq("15")
    end

    it "incr with default step increments by 1" do
      redis.set(val_key, "10")
      val.incr
      expect(redis.get(val_key)).to eq("11")
    end

    it "decr decrements by the given step" do
      redis.set(val_key, "10")
      val.decr(3)
      expect(redis.get(val_key)).to eq("7")
    end

    it "decr with default step decrements by 1" do
      redis.set(val_key, "10")
      val.decr
      expect(redis.get(val_key)).to eq("9")
    end
  end

  describe "Metric::Base#redis_key" do
    it "includes the identity key prefix" do
      metric = identity.visits
      expect(metric.send(:redis_key)).to eq("app_identity.#{identity_id}:visits")
    end

    it "uses redis_key_prefix from the identity" do
      metric = identity.visits
      expect(metric.redis_key_prefix).to eq("app_identity.#{identity_id}")
    end

    it "delete removes the correct key" do
      redis.set(visits_key, "data")
      identity.visits.delete
      expect(redis.exists?(visits_key)).to be false
    end
  end

  describe "Metric::Base ALLOWED_STEPS" do
    it "includes :minute, :hour, :day, :week, :month" do
      expect(Nightfury::Metric::Base::ALLOWED_STEPS).to include(:minute, :hour, :day, :week, :month)
    end

    it "defaults to :minute for invalid step" do
      m = Nightfury::Metric::CountTimeSeries.new(:test, step: :invalid)
      expect(m.step).to eq(:minute)
    end

    it "accepts :day as valid step" do
      m = Nightfury::Metric::CountTimeSeries.new(:test, step: :day)
      expect(m.step).to eq(:day)
    end
  end

  describe "TimeSeries#floor_time" do
    let(:ts) { Nightfury::Metric::TimeSeries.new(:test_ts, step: :day) }

    it "rounds down to day boundary" do
      t = Time.utc(2026, 11, 20, 15, 30, 45)
      floored = ts.send(:floor_time, t, 86_400)
      expect(floored).to eq(Time.utc(2026, 11, 20))
    end

    it "rounds down to hour boundary" do
      t = Time.utc(2026, 11, 20, 15, 30, 45)
      floored = ts.send(:floor_time, t, 3600)
      expect(floored).to eq(Time.utc(2026, 11, 20, 15))
    end
  end

  describe "TimeSeries seconds_in_step" do
    it "maps :day to 86400" do
      expect(Nightfury::Metric::TimeSeries.seconds_in_step(:day, day)).to eq(86_400)
    end

    it "maps :hour to 3600" do
      expect(Nightfury::Metric::TimeSeries.seconds_in_step(:hour, day)).to eq(3600)
    end

    it "maps :minute to 60" do
      expect(Nightfury::Metric::TimeSeries.seconds_in_step(:minute, day)).to eq(60)
    end
  end

  describe "TimeSeries#set stores data" do
    let(:ts) { Nightfury::Metric::TimeSeries.new(:test_ts, step: :day) }
    let(:key) { "nf-test:test_ts" }

    before { redis.del(key) }
    after { redis.del(key) }

    it "stores value at the correct timestamp score" do
      t = Time.utc(2026, 11, 20)
      ts.set("5", t)
      members = redis.zrangebyscore(key, t.to_i, t.to_i, with_scores: true)
      expect(members).not_to be_empty
    end
  end

  describe "TimeSeries#get_all" do
    let(:ts) { Nightfury::Metric::TimeSeries.new(:test_ts, step: :day) }
    let(:key) { "nf-test:test_ts" }

    before { redis.del(key) }
    after { redis.del(key) }

    it "returns empty hash when key does not exist" do
      expect(ts.get_all).to eq({})
    end

    it "returns all data points" do
      day1 = Time.utc(2026, 11, 19)
      day2 = Time.utc(2026, 11, 20)
      redis.zadd(key, [[day1.to_i, "#{day1.to_i}:3"], [day2.to_i, "#{day2.to_i}:7"]])
      result = ts.get_all
      expect(result[day1.to_i.to_s]).to eq("3")
      expect(result[day2.to_i.to_s]).to eq("7")
    end
  end

  describe "CountTimeSeries zero padding" do
    it "stores zero counts as '0' string" do
      identity.visits.incr(0, day)
      result = identity.visits.get_all
      expect(result).to have_key(day.to_i.to_s)
    end
  end

  describe "Identity#key_prefix" do
    it "uses class name demodulized and underscored" do
      expect(identity.key_prefix).to start_with("app_identity.")
      expect(identity.key_prefix).to include(identity_id)
    end

    it "new_record? returns true when no keys exist" do
      expect(identity.new_record?).to be true
    end

    it "new_record? returns false when keys exist" do
      redis.set(visits_key, "1")
      expect(identity.new_record?).to be false
    end
  end

  describe "Nightfury configuration" do
    it "raises NotConfiguredError when redis is nil" do
      configured_redis = Nightfury.redis
      Nightfury.instance_variable_set(:@redis, nil)
      expect { Nightfury.redis }.to raise_error(Nightfury::NotConfiguredError)
    ensure
      Nightfury.instance_variable_set(:@redis, configured_redis)
    end

    it "wraps redis with Redis::Namespace" do
      raw_redis = Redis.new(url: ENV.fetch("REDIS_URL"))
      ns_redis = Nightfury.send(:set_namespace, raw_redis)
      expect(ns_redis).to be_a(Redis::Namespace)
    ensure
      raw_redis&.close
    end

    it "uses nf-test as namespace in test env" do
      expect(Nightfury.redis.namespace.to_s).to eq("nf-test")
    end
  end
end
