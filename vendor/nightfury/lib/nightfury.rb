require 'redis'
require 'redis-namespace'
require 'json'
require 'active_support/core_ext/object/blank'
require 'active_support/core_ext/class/attribute'
require 'active_support/core_ext/string/inflections'
require 'active_support/core_ext/time/calculations'
require 'active_support/core_ext/date/calculations'
require 'active_support/core_ext/date_time/calculations'
require 'active_support/core_ext/numeric/time'
require 'active_support/concern'

module Nightfury
  class NotConfiguredError < StandardError; end

  class << self
    attr_accessor :redis, :namespace

    def redis
      @redis || raise(NotConfiguredError, 'Nightfury Redis is not configured')
    end

    def redis=(redis_instance)
      @redis = set_namespace(redis_instance)
    end

    def namespace
      @namespace ||= :nf
    end

    def namespace=(namespace_symbol)
      @namespace = namespace_symbol
      @redis = set_namespace(redis)
    end

    private

    def set_namespace(redis_instance)
      Redis::Namespace.new(namespace, redis: redis_instance)
    end
  end
end

require_relative "nightfury/version"
require_relative "nightfury/metric"
require_relative "nightfury/metric/value"
require_relative "nightfury/metric/time_series"
require_relative "nightfury/metric/count_time_series"
require_relative "nightfury/metric/avg_time_series"
require_relative "nightfury/identity"

