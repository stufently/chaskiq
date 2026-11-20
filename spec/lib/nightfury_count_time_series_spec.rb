# frozen_string_literal: true

require "rails_helper"

RSpec.describe Nightfury::Metric::CountTimeSeries do
  let(:redis) { Redis.new(url: ENV.fetch("REDIS_URL")) }
  let(:ts) { described_class.new(:mutb_count_test, step: :minute) }
  let(:key) { "nf-test:mutb_count_test" }

  before { redis.del(key) }
  after { redis.del(key); redis.close }

  describe "#decr" do
    it "subtracts exactly 1 from the current value" do
      t = Time.utc(2026, 11, 20, 12, 0)
      ts.incr(3, t)
      ts.decr(1, t)
      result = ts.get_exact(t)
      expect(result.values.first).to eq("2")
    end
  end

  describe "#get_padded_range" do
    it "pads empty steps with '0'" do
      t1 = Time.utc(2026, 11, 20, 12, 0)
      t2 = Time.utc(2026, 11, 20, 12, 2)
      ts.incr(5, t1)
      result = ts.get_padded_range(t1, t2)
      empty_step = ts.send(:get_step_time, Time.utc(2026, 11, 20, 12, 1)).to_i.to_s
      expect(result[empty_step]).to eq("0")
    end

    it "runs and returns one entry per step" do
      t1 = Time.utc(2026, 11, 20, 12, 0)
      t2 = Time.utc(2026, 11, 20, 12, 2)
      ts.incr(1, t1)
      result = ts.get_padded_range(t1, t2)
      expect(result.size).to eq(3)
    end

    it "padding value is '0' not other values" do
      t1 = Time.utc(2026, 11, 20, 12, 0)
      t2 = Time.utc(2026, 11, 20, 12, 1)
      result = ts.get_padded_range(t1, t2)
      result.each_value { |v| expect(v).to eq("0") }
    end
  end

  describe "#incr with default time" do
    it "stores at the current minute" do
      now = Time.utc(2026, 11, 20, 12, 0, 17)
      travel_to now do
        ts.incr
        step_time = ts.send(:get_step_time, now)
        result = ts.get_exact(step_time)
        expect(result).not_to be_nil
        expect(result.values.first).to eq("1")
      end
    end

    it "does not shift time by 1 hour" do
      now = Time.utc(2026, 11, 20, 12, 0, 17)
      travel_to now do
        ts.incr
        step_now = ts.send(:get_step_time, now)
        step_hour_ago = ts.send(:get_step_time, now - 3600)
        expect(ts.get_exact(step_now)).not_to be_nil
        expect(ts.get_exact(step_hour_ago)).to be_nil
      end
    end
  end

  describe "#incr at non-aligned time" do
    it "stores at the step start" do
      t = Time.utc(2026, 11, 20, 12, 0, 17)
      ts.incr(1, t)
      step_start = ts.send(:get_step_time, t)
      result = ts.get_exact(step_start)
      expect(result).not_to be_nil
      expect(result.keys.first).to eq(step_start.to_i.to_s)
    end

    it "uses step_time not raw time for set" do
      t = Time.utc(2026, 11, 20, 12, 0, 17)
      ts.incr(1, t)
      step_start = ts.send(:get_step_time, t)
      all = ts.get_all
      expect(all).to have_key(step_start.to_i.to_s)
      expect(all).not_to have_key(t.to_i.to_s)
    end
  end
end
