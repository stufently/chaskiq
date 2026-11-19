# frozen_string_literal: true

require_relative "../../lib/middleware/rack_bad_request"

Rails.application.config.middleware.insert_before Rack::MethodOverride, Middleware::RackBadRequest
