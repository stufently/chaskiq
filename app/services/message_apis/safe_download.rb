# frozen_string_literal: true

require "ipaddr"
require "net/http"
require "socket"
require "stringio"
require "timeout"

module MessageApis
  class SafeDownload
    class Body < StringIO
      attr_reader :content_type

      def initialize(body, content_type:)
        super(body)
        @content_type = content_type
      end

      def mime_type
        type = content_type.to_s.partition(";").first.strip.downcase
        type unless type.empty?
      end
    end

    class FetchLimits
      attr_reader :max_bytes, :max_redirects

      def initialize(max_bytes: 15 * 1024 * 1024, max_redirects: 3, deadline: 30)
        @max_bytes = max_bytes
        @max_redirects = max_redirects
        @deadline = deadline
      end

      def within_deadline(&)
        return unless @deadline.positive?

        Timeout.timeout(@deadline, &)
      rescue StandardError
        nil
      end
    end
    private_constant :FetchLimits

    BLOCKED_RANGES = %w[
      0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8
      168.63.129.16/32 169.254.0.0/16 172.16.0.0/12 192.0.0.0/24 192.168.0.0/16
      198.18.0.0/15 224.0.0.0/4 240.0.0.0/4
      ::/96 64:ff9b::/96 64:ff9b:1::/48 2001::/32 2002::/16 fc00::/7 fe80::/10 ff00::/8
    ].map { |range| IPAddr.new(range).freeze }.freeze
    private_constant :BLOCKED_RANGES

    def self.blocked_ip?(ip)
      address = IPAddr.new(ip.to_s)
      address = address.native if address.ipv4_mapped?
      BLOCKED_RANGES.any? { |range| range.family == address.family && range.include?(address) }
    rescue IPAddr::Error
      true
    end

    def self.resolve(host)
      Addrinfo.getaddrinfo(host, nil, :UNSPEC, :STREAM).map(&:ip_address).uniq
    rescue SocketError
      []
    end

    # Only pass trusted_origin for an origin taken from trusted application configuration.
    def self.fetch(url, headers: {}, allow_own_host: true, url_allowed: nil, **options)
      address_options = { allow_own_host: allow_own_host, trusted_origin: options.delete(:trusted_origin) }
      limits = FetchLimits.new(**options)
      limits.within_deadline do
        follow_redirects(url, limits, headers, address_options, url_allowed)
      end
    end

    def self.follow_redirects(url, limits, headers, address_options, url_allowed)
      uri = http_uri(url)

      (limits.max_redirects + 1).times do |hop|
        return unless uri
        return if url_allowed && !url_allowed.call(uri)

        addresses = download_addresses(uri, **address_options)
        return unless addresses

        body, location = download(uri, addresses, limits.max_bytes, hop.zero? ? headers : {})
        return body unless location
        return if hop == limits.max_redirects

        uri = http_uri(URI.join(uri.to_s, location).to_s)
      end

      nil
    end

    def self.download_addresses(uri, allow_own_host:, trusted_origin:)
      addresses = resolve(uri.hostname)
      return if addresses.empty?
      return addresses if same_origin?(uri, trusted_origin)
      return addresses if addresses.none? { |address| blocked_ip?(address) }

      addresses if allow_own_host && same_origin?(uri, http_uri(Chaskiq::Config.get("HOST").to_s))
    end

    def self.http_uri(url)
      uri = URI.parse(url)
      uri if uri.is_a?(URI::HTTP) && uri.hostname && !uri.hostname.empty?
    rescue URI::Error, ArgumentError
      nil
    end

    def self.same_origin?(uri, origin)
      origin && uri.scheme.casecmp?(origin.scheme) && uri.hostname.casecmp?(origin.hostname) && uri.port == origin.port
    end

    def self.download(uri, addresses, max_bytes, headers)
      addresses.each do |address|
        received_response = false
        begin
          request(uri, address, headers) do |response|
            received_response = true
            # Returning here prevents Net::HTTP from draining a rejected or redirect body.
            return read_response(response, max_bytes)
          end
        rescue Net::OpenTimeout, SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError
          raise if received_response
        end
      end

      nil
    end

    def self.request(uri, address, headers, &)
      http = Net::HTTP.new(uri.hostname, uri.port, nil)
      http.ipaddr = address
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 5
      http.read_timeout = 10
      http.max_retries = 0
      request_headers = headers.reject { |name, _| name.to_s.casecmp?("Accept-Encoding") }
      request = Net::HTTP::Get.new(uri.request_uri, request_headers.merge("Accept-Encoding" => "identity"))

      http.request(request, &)
    end

    def self.read_response(response, max_bytes)
      if response.is_a?(Net::HTTPRedirection)
        location = response["location"]
        return [nil, location] unless location.to_s.empty?
      end
      return unless response.is_a?(Net::HTTPSuccess)

      content_length = response.content_length
      return if content_length && content_length > max_bytes

      body = String.new(encoding: Encoding::BINARY)
      response.read_body do |chunk|
        return if body.bytesize + chunk.bytesize > max_bytes

        body << chunk
      end
      [Body.new(body, content_type: response["content-type"]), nil]
    end

    private_class_method :follow_redirects, :download_addresses, :http_uri, :same_origin?,
                         :download, :request, :read_response
  end
end
