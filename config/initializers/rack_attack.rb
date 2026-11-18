# frozen_string_literal: true

if Rails.env.production? || Rails.env.staging?
  redis_url = Chaskiq::Config.get("REDIS_URL")
  if redis_url.present?
    Rack::Attack.cache.store = ActiveSupport::Cache::RedisCacheStore.new(url: redis_url)
  else
    Rails.logger.warn("Rack::Attack uses Rails.cache because REDIS_URL is empty")
  end
end

Rack::Attack.throttle("logins/ip", limit: 20, period: 1.hour) do |req|
  next unless req.post? && %r{\A/+oauth/+token(?:\.[^/.?]+)?/*\z}.match?(req.path)

  grant_type = begin
    begin
      body_params = req.media_type == "application/json" ? JSON.parse(req.body.read) : req.POST
    ensure
      req.body&.rewind
    end
    req.GET.fetch("grant_type") { body_params["grant_type"] if body_params.is_a?(Hash) }
  rescue StandardError
    # Invalid parameters must still consume an attempt.
    nil
  end
  req.ip unless grant_type == "refresh_token"
end

ActiveSupport::Notifications.subscribe("rack.attack") do |_name, _start, _finish, _request_id, payload|
  match_type = payload.is_a?(Hash) ? payload[:request]&.env&.dig("rack.attack.match_discriminator") : nil
  Rails.logger.info("Rack::Attack throttled #{match_type}") if match_type
end
