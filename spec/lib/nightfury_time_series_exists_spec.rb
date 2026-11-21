# frozen_string_literal: true

require "rails_helper"

RSpec.describe Nightfury::Metric::TimeSeries do
  let(:name) { :"fxb_series_#{SecureRandom.hex(4)}" }
  let(:series) { described_class.new(name, step: :minute) }
  let(:time) { Time.zone.at(1_700_000_040) }

  after { series.delete }

  it "returns nil from each reader after the series is deleted" do
    series.set(5, time)
    series.delete

    expect(series.get).to be_nil
    expect(series.get_exact(time)).to be_nil
    expect(series.get_range(time - 3600, time)).to be_nil
    expect(series.get_all).to be_nil
  end

  it "initialises an empty series with empty metadata" do
    expect(series.meta).to eq({})
    expect(series.get).to be_nil
    expect(series.get_all).to eq({})
  end

  it "restores empty metadata when writing to a deleted series" do
    series.set(5, time)
    series.delete
    series.set(7, time)

    expect(series.get_all).to eq({ time.to_i.to_s => "7" })
    expect(described_class.new(name, step: :minute).meta).to eq({})
  end

  it "accumulates increments at the same timestamp" do
    counter = Nightfury::Metric::CountTimeSeries.new(name, step: :minute)
    counter.incr(1, time)
    counter.incr(1, time)

    expect(counter.get_exact(time)).to eq({ time.to_i.to_s => "2" })
  ensure
    counter&.delete
  end
end
