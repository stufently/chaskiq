# frozen_string_literal: true

# Your Ruby Rack App that returns your Rails App's Health
# Create the file
# "lib/rack/health_check.rb"
# from https://medium.com/@goncalvesjoao/how-to-have-a-working-health-endpoint-while-rails-is-500ring-509efc1da42c

module Rack
  class HealthCheck
    def initialize
      @redis = Redis.new
    end

    def call(env)
      connected = redis_connected
      status = {
        redis: {
          connected: connected
        }
      }

      return [503, {}, [status.to_json]] unless connected

      [200, {}, [status.to_json]]
    end

    protected

    def redis_connected
      @redis.ping == "PONG"
    rescue StandardError
      false
    end
  end
end
