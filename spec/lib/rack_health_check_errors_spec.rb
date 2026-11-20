# frozen_string_literal: true

require "rails_helper"
require "rack/health_check"

RSpec.describe Rack::HealthCheck do
  describe "#redis_connected" do
    it "does not rescue non-StandardError exceptions" do
      check = described_class.new
      non_standard = Class.new(StandardError)
      redis_double = instance_double(Redis)
      allow(redis_double).to receive(:ping).and_raise(non_standard)
      check.instance_variable_set(:@redis, redis_double)

      expect { check.send(:redis_connected) }.to raise_error(non_standard)
    end
  end
end
