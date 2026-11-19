# frozen_string_literal: true

require "rails_helper"

RSpec.describe Nightfury do
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

  it "raises a not configured error without using global Redis" do
    configured_redis = described_class.redis
    described_class.instance_variable_set(:@redis, nil)

    expect(Redis).not_to receive(:current)
    expect { described_class.redis }.to raise_error(described_class::NotConfiguredError, /not configured/)
  ensure
    described_class.instance_variable_set(:@redis, configured_redis)
  end

  it "uses the deployed key prefix for app metrics" do
    identity.visits.incr(1, day)

    expect(redis.exists?(visits_key)).to be(true)
  end

  it "counts increments in the same daily bucket" do
    identity.visits.incr(1, day)
    identity.visits.incr(1, day + 1.hour)

    expect(identity.visits.get_all).to eq(day.to_i.to_s => "2")
  end

  it "reads every point in a series without meta" do
    next_day = day + 1.day
    redis.zadd(visits_key, [[day.to_i, "#{day.to_i}:4"], [next_day.to_i, "#{next_day.to_i}:7"]])

    expect(identity.visits.get_all).to eq(day.to_i.to_s => "4", next_day.to_i.to_s => "7")
  end

  it "keeps points at zero and negative scores alongside metadata" do
    identity.visits.set(2, Time.at(-86_400).utc)
    identity.visits.set(1, Time.at(0).utc)
    redis.zadd(visits_key, 0, {}.to_json)

    expect(identity.visits.get_all).to eq("-86400" => "2", "0" => "1")
  end

  it "averages response times in the same daily bucket" do
    identity.first_response_time.set(10, day)
    identity.first_response_time.set(20, day)

    expect(identity.first_response_time.get_all).to eq(day.to_i.to_s => "15.0")
  end
end
