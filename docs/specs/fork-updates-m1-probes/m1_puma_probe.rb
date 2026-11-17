# frozen_string_literal: true
# Probe for fork-updates-m1: config/puma.rb must keep today's behaviour when
# WEB_CONCURRENCY is unset (single mode, 0 workers, no worker-boot hook) and
# enable workers / wait_for_less_busy_worker / on_worker_boot only in cluster mode.
# Facts (puma 6.4.3, configuration.rb): DEFAULTS workers: 0; puma_options_from_env
# reads WEB_CONCURRENCY. file_options holds only what config/puma.rb itself sets.
require "puma"
require "puma/configuration"

def load_conf(web_concurrency)
  if web_concurrency.nil?
    ENV.delete("WEB_CONCURRENCY")
  else
    ENV["WEB_CONCURRENCY"] = web_concurrency
  end
  conf = Puma::Configuration.new(config_files: ["config/puma.rb"])
  conf.load
  conf
end

fails = []
check = ->(cond, msg) { fails << msg unless cond }

c = load_conf(nil)
check.call(c.options[:workers].to_i == 0, "unset: workers must be 0, got #{c.options[:workers].inspect}")
check.call(!c.options.file_options.key?(:wait_for_less_busy_worker), "unset: puma.rb must not set wait_for_less_busy_worker in single mode")
check.call(Array(c.options.file_options[:before_worker_boot]).empty?, "unset: no on_worker_boot hook in single mode")

c = load_conf("3")
check.call(c.options[:workers].to_i == 3, "WEB_CONCURRENCY=3: workers must be 3, got #{c.options[:workers].inspect}")
check.call(c.options.file_options.key?(:wait_for_less_busy_worker), "WEB_CONCURRENCY=3: wait_for_less_busy_worker must be set in cluster mode")
check.call(!Array(c.options.file_options[:before_worker_boot]).empty?, "WEB_CONCURRENCY=3: on_worker_boot hook must be registered")

c = load_conf("0")
check.call(c.options[:workers].to_i == 0, "WEB_CONCURRENCY=0: workers must be 0")
check.call(!c.options.file_options.key?(:wait_for_less_busy_worker), "WEB_CONCURRENCY=0: no wait_for_less_busy_worker")

if fails.empty?
  puts "PUMA PROBE PASS"
else
  puts fails
  exit 1
end
