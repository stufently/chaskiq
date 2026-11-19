# frozen_string_literal: true

module RackForwardedValues
  SCHEME_HEADERS = {
    scheme: "HTTP_X_FORWARDED_SCHEME",
    proto: "HTTP_X_FORWARDED_PROTO"
  }.freeze
  private_constant :SCHEME_HEADERS

  def forwarded_authority
    return super unless forwarded_priority == [:x_forwarded]

    host = split_header(get_header("HTTP_X_FORWARDED_HOST")).first
    wrap_ipv6(host) if host
  end

  private

  def forwarded_scheme
    return super unless forwarded_priority == [:x_forwarded]

    # Rack 2 validated X-Forwarded-Scheme as-is and used the first X-Forwarded-Proto value.
    x_forwarded_proto_priority.each do |type|
      header = get_header(SCHEME_HEADERS[type])
      header = header&.split(",", 2)&.first if type == :proto
      scheme = allowed_scheme(header)
      return scheme if scheme
    end
    nil
  end
end

Rack::Request::Helpers.prepend(RackForwardedValues)
