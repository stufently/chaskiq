# frozen_string_literal: true

require Rails.root.join("vendor/nightfury/lib/nightfury").to_s

Nightfury.redis = Redis.new
Nightfury.redis.namespace = "nf-#{Rails.env}"
