# frozen_string_literal: true

require "rails_helper"

RSpec.describe Nightfury::Metric::AvgTimeSeries do
  let(:nf_redis) { Nightfury.redis }
  let(:ts) { described_class.new(:mutb_avg_test, step: :minute) }
  let(:key) { "mutb_avg_test" }

  before { nf_redis.del(key) }
  after { nf_redis.del(key) }

  describe "#get_padded_range" do
    it "pads empty steps with '0.0'" do
      t1 = Time.utc(2026, 11, 20, 12, 0)
      t2 = Time.utc(2026, 11, 20, 12, 2)
      ts.set(10, t1)
      result = ts.get_padded_range(t1, t2)
      empty_step = ts.send(:get_step_time, Time.utc(2026, 11, 20, 12, 1)).to_i.to_s
      expect(result[empty_step]).to eq("0.0")
    end
  end
end
