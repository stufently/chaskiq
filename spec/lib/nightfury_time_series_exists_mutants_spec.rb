# frozen_string_literal: true

require "rails_helper"

RSpec.describe Nightfury::Metric::TimeSeries do
  let(:name) { :"mfxb-ts-#{SecureRandom.hex(4)}" }
  let(:series) { described_class.new(name, step: :minute) }
  let(:time) { Time.zone.at(1_700_000_040) }

  after { series.delete }

  describe "get_meta and exists? mutant-killing" do
    it "X25: returns nil (not [nil, {}]) for a deleted series with get_meta" do
      series.set(5, time)
      series.delete

      expect(series.get(nil, true)).to be_nil
    end

    it "X26: returns nil (not [nil, {}]) for get_exact on a deleted series with get_meta" do
      series.set(5, time)
      series.delete

      expect(series.get_exact(time, true)).to be_nil
    end

    it "X27: returns [nil, {}] for a new series with get_meta" do
      expect(series.get(nil, true)).to eq([nil, {}])
    end

    it "X28: returns the data and meta from get with get_meta" do
      series.set(5, time)

      result = series.get(nil, true)
      expect(result).to be_a(Array)
      expect(result.length).to eq(2)
      expect(result[0]).to eq({ time.to_i.to_s => "5" })
      expect(result[1]).to eq({})
    end

    it "X29: returns the data and meta from get_exact with get_meta" do
      series.set(5, time)

      result = series.get_exact(time, true)
      expect(result).to be_a(Array)
      expect(result.length).to eq(2)
      expect(result[0]).to eq({ time.to_i.to_s => "5" })
      expect(result[1]).to eq({})
    end

    it "X30: returns nil for get_exact of a missing timestamp" do
      series.set(5, time)

      expect(series.get_exact(time + 60)).to be_nil
    end

    it "X31: get returns the latest point, not the oldest" do
      series.set(5, time - 60)
      series.set(7, time)

      expect(series.get).to eq({ time.to_i.to_s => "7" })
    end

    it "X32: get(timestamp) returns the latest point at or before the timestamp" do
      series.set(5, time)

      expect(series.get(time + 120)).to eq({ time.to_i.to_s => "5" })
    end

    it "X33: get_range returns all points in the range" do
      series.set(5, time - 60)
      series.set(7, time)

      result = series.get_range(time - 60, time)
      expected = { (time - 60).to_i.to_s => "5", time.to_i.to_s => "7" }
      expect(result).to eq(expected)
    end
  end
end
