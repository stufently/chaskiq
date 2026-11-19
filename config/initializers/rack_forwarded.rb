# frozen_string_literal: true

# Preserve Rack 2's proxy header precedence for client IP and scheme.
Rack::Request.forwarded_priority = [:x_forwarded]
Rack::Request.x_forwarded_proto_priority = %i[scheme proto]
