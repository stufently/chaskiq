# frozen_string_literal: true

require "rack/bad_request"

module Middleware
  # Handles parsing errors raised before Rails can render a bad request response.
  class RackBadRequest
    def initialize(app)
      @app = app
    end

    def call(env)
      @app.call(env)
    rescue Rack::BadRequest
      [400, { "content-type" => "text/plain" }, ["Bad Request"]]
    end
  end
end
