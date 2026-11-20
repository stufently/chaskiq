# frozen_string_literal: true

require "rails_helper"

RSpec.describe Nightfury::Metric::TimeSeries do
  let(:nf_redis) { Nightfury.redis }
  let(:ts) { described_class.new(:mutb_ts_test, step: :minute) }
  let(:key) { "mutb_ts_test" }

  before { nf_redis.del(key) }
  after { nf_redis.del(key) }

  describe "#get/#get_exact on empty series" do
    it "returns nil for get on a fresh series (only meta at score 0)" do
      result = ts.get
      expect(result).to be_nil
    end

    it "returns nil for get with get_meta on fresh series" do
      result = ts.get(nil, true)
      expect(result).to eq([nil, {}])
    end

    it "returns nil for get_exact of an empty step" do
      result = ts.get_exact(Time.utc(2026, 11, 20, 14, 0))
      expect(result).to be_nil
    end

    it "returns nil for get at a timestamp before any data" do
      result = ts.get(Time.utc(2026, 11, 20, 11, 0))
      expect(result).to be_nil
    end
  end

  describe "#get_range/#get_all on empty series" do
    it "returns empty or nil for get_all on a fresh series" do
      result = ts.get_all
      expect(result.nil? || result.empty?).to be true
    end

    it "returns empty or nil for get_range on a fresh series" do
      result = ts.get_range(Time.utc(2026, 11, 20), Time.utc(2026, 11, 21))
      expect(result.nil? || result.empty?).to be true
    end
  end

  describe "#set deduplication within same step" do
    it "keeps only the last value when set twice at the same step" do
      t = Time.utc(2026, 11, 20, 12, 0, 17)
      ts.set("first", t)
      ts.set("second", t)
      step_time = ts.send(:get_step_time, t)
      result = ts.get_exact(step_time)
      expect(result.values.first).to eq("second")
    end

    it "keeps both points when set at different steps" do
      t1 = Time.utc(2026, 11, 20, 12, 0, 0)
      t2 = Time.utc(2026, 11, 20, 12, 1, 0)
      ts.set("a", t1)
      ts.set("b", t2)
      all = ts.get_all
      expect(all.size).to eq(2)
    end
  end

  describe "#get_all value decoding" do
    it "returns the stored value string with colons" do
      ts.set("a:b", Time.utc(2026, 11, 20, 12, 0))
      all = ts.get_all
      expect(all.values.first).to eq("a:b")
    end
  end

  describe "meta round-trip" do
    it "stores and retrieves meta as JSON" do
      ts.meta = { "k" => 1 }
      expect(ts.meta).to eq({ "k" => 1 })
    end

    it "meta is stored at score 0 and not in get_all data" do
      ts.meta = { "k" => 1 }
      ts.set("val", Time.utc(2026, 11, 20, 12, 0))
      all = ts.get_all
      expect(all.values).not_to include(hash_including("k"))
    end
  end

  describe ".seconds_in_step" do
    it "returns 60 for :minute" do
      expect(described_class.seconds_in_step(:minute, Time.now)).to eq(60)
    end

    it "returns 3600 for :hour" do
      expect(described_class.seconds_in_step(:hour, Time.now)).to eq(3600)
    end
  end

  describe "zremrangebyscore replaces within step" do
    it "set twice in same step leaves one point with last value" do
      t = Time.utc(2026, 11, 20, 12, 0, 30)
      ts.set("old", t)
      ts.set("new", t)
      members = nf_redis.zrangebyscore(key, ts.send(:get_step_time, t).to_i, ts.send(:get_step_time, t).to_i)
      expect(members.size).to eq(1)
      expect(members.first).to include("new")
    end
  end

  describe "meta stored as JSON" do
    it "stores meta as JSON parseable string" do
      ts.meta = { "k" => 1 }
      raw_member = nf_redis.zrangebyscore(key, 0, 0).first
      parsed = JSON.parse(raw_member)
      expect(parsed).to eq({ "k" => 1 })
    end
  end

  describe "zremrangebyscore range" do
    it "does not remove points from adjacent steps" do
      t1 = Time.utc(2026, 11, 20, 12, 0, 0)
      t2 = Time.utc(2026, 11, 20, 12, 1, 0)
      ts.set("first", t1)
      ts.set("second", t2)
      all = ts.get_all
      expect(all.size).to eq(2)
      expect(all[t1.to_i.to_s]).to eq("first")
      expect(all[t2.to_i.to_s]).to eq("second")
    end
  end
end
