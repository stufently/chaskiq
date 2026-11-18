# frozen_string_literal: true

# Throttle login attempts (password grant) per IP.
# The frontend posts JSON to /oauth/token.json (password grant) and /oauth/token
# (refresh_token grant). Form posts to the same paths are also covered.
# refresh_token requests are excluded so token refresh is never throttled.
Rack::Attack.throttle("logins/ip", limit: 20, period: 1.hour) do |req|
  if req.post? && (req.path == "/oauth/token" || req.path == "/oauth/token.json")
    # Read grant_type from form params or JSON body
    grant_type = req.params["grant_type"]
    if grant_type.nil? && req.media_type == "application/json"
      begin
        body = req.body.read
        req.body.rewind
        parsed = JSON.parse(body)
        grant_type = parsed["grant_type"]
      rescue JSON::ParserError
        nil
      end
    end
    req.ip unless grant_type == "refresh_token"
  end
end

ActiveSupport::Notifications.subscribe("rack.attack") do |_name, _start, _finish, _request_id, payload|
  match_type = payload.is_a?(Hash) ? payload[:request]&.env&.dig("rack.attack.match_discriminator") : nil
  Rails.logger.info("Rack::Attack throttled #{match_type}") if match_type
end
