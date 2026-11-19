# frozen_string_literal: true

require "ipaddr"
require "net/http"
require "socket"
require "stringio"

class MessageApis::SafeDownload
  BLOCKED_RANGES = %w[
    0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8
    169.254.0.0/16 172.16.0.0/12 192.0.0.0/24 192.168.0.0/16
    198.18.0.0/15 224.0.0.0/4 240.0.0.0/4
    ::/128 ::1/128 fc00::/7 fe80::/10 ff00::/8
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

  def self.fetch(url, max_bytes: 15 * 1024 * 1024, max_redirects: 3)
    uri = http_uri(url)

    (max_redirects + 1).times do |hop|
      return unless uri

      addresses = resolve(uri.hostname)
      return if addresses.empty?
      return if addresses.any? { |address| blocked_ip?(address) } && !own_origin?(uri)

      body, location = download(uri, addresses.first, max_bytes)
      return body unless location
      return if hop == max_redirects

      uri = http_uri(URI.join(uri.to_s, location).to_s)
    end

    nil
  rescue StandardError
    nil
  end

  def self.http_uri(url)
    uri = URI.parse(url)
    uri if uri.is_a?(URI::HTTP) && uri.hostname && !uri.hostname.empty?
  rescue URI::Error, ArgumentError
    nil
  end

  def self.own_origin?(uri)
    own = http_uri(Chaskiq::Config.get("HOST").to_s)
    own && uri.scheme == own.scheme && uri.hostname.casecmp?(own.hostname) && uri.port == own.port
  end

  def self.download(uri, address, max_bytes)
    http = Net::HTTP.new(uri.hostname, uri.port, nil)
    http.ipaddr = address
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 5
    http.read_timeout = 10
    http.max_retries = 0
    request = Net::HTTP::Get.new(uri.request_uri, "Accept-Encoding" => "identity")

    # Return from the request block to avoid draining rejected or redirect bodies.
    http.request(request) do |response|
      if response.is_a?(Net::HTTPRedirection)
        location = response["location"]
        return [nil, location] if location && !location.empty?
      end
      return unless response.is_a?(Net::HTTPSuccess)
      return if response.content_length && response.content_length > max_bytes

      body = String.new(encoding: Encoding::BINARY)
      response.read_body do |chunk|
        return if body.bytesize + chunk.bytesize > max_bytes

        body << chunk
      end
      return [StringIO.new(body), nil]
    end
  end

  private_class_method :http_uri, :own_origin?, :download
end
