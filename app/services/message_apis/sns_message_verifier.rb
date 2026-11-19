# frozen_string_literal: true

require "base64"
require "openssl"
require "uri"

module MessageApis
  # Authenticates SNS messages using signing certificates fetched from SNS over HTTPS.
  class SnsMessageVerifier
    class VerificationError < StandardError; end
    class CertificateUnavailable < StandardError; end

    CONFIRMATION_FIELDS = %w[Message MessageId SubscribeURL Timestamp Token TopicArn Type].freeze
    SIGNABLE_FIELDS = {
      "Notification" => %w[Message MessageId Subject Timestamp TopicArn Type].freeze,
      "SubscriptionConfirmation" => CONFIRMATION_FIELDS,
      "UnsubscribeConfirmation" => CONFIRMATION_FIELDS
    }.freeze
    SIGNATURE_FIELDS = %w[Signature SignatureVersion SigningCertURL].freeze
    DIGESTS = { "1" => "SHA1", "2" => "SHA256" }.freeze
    CERTIFICATE_HOST = /\Asns\.[a-z0-9-]+\.amazonaws\.com(\.cn)?\z/i
    CACHE_LIMIT = 32
    CACHE_LOCK = Mutex.new
    DOWNLOAD_LOCKS = Array.new(CACHE_LIMIT) { Mutex.new }.freeze
    @certificates = {}

    def self.verify!(message)
      digest, signature = precheck!(message)
      reject! unless topic_allowed?(message["TopicArn"])
      url = message["SigningCertURL"]
      reject! unless certificate_url?(url)
      certificate = signing_certificate(url)
      reject! unless certificate_current?(certificate)

      valid_signature?(certificate.public_key, digest, signature, canonical_string(message)) || reject!
    rescue OpenSSL::OpenSSLError
      reject!
    end

    def self.clear_cache!
      CACHE_LOCK.synchronize do
        @certificates.clear
        @warned_about_topics = false
      end
    end

    def self.precheck!(message)
      reject! unless message.is_a?(Hash) && SIGNABLE_FIELDS.key?(message["Type"])

      validate_fields!(message)
      digest = digest_for(message["SignatureVersion"]) || reject!
      [digest, decode_signature(message["Signature"])]
    end

    def self.validate_fields!(message)
      fields = SIGNABLE_FIELDS.fetch(message["Type"])
      reject! unless ((fields - ["Subject"]) + SIGNATURE_FIELDS).all? { |field| nonempty_string?(message[field]) }
      (fields - ["Message"]).each { |field| reject! unless single_line?(message[field]) }
    end

    def self.valid_string?(value) = value.is_a?(String) && value.valid_encoding?
    def self.nonempty_string?(value) = valid_string?(value) && !value.empty?
    def self.single_line?(value) = value.nil? || (valid_string?(value) && !value.match?(/[\r\n]/))
    def self.digest_for(version) = DIGESTS[version]

    def self.decode_signature(value)
      signature = Base64.strict_decode64(value)
      reject! unless signature.bytesize.between?(128, 1024)

      signature
    rescue ArgumentError
      reject!
    end

    def self.topic_allowed?(arn)
      allowed = ENV.fetch("SNS_ALLOWED_TOPIC_ARNS", "").split(",").map(&:strip).reject(&:empty?)
      return allowed.include?(arn) unless allowed.empty?

      CACHE_LOCK.synchronize do
        Rails.logger.warn("SNS_ALLOWED_TOPIC_ARNS is empty. Allowing all topics.") unless @warned_about_topics
        @warned_about_topics = true
      end
    end

    def self.certificate_url?(url)
      uri = URI.parse(url)
      return false unless uri.is_a?(URI::HTTPS) && uri.port == 443
      # URI normalizes away an empty userinfo before the @ delimiter.
      return false if [uri.query, uri.fragment].any? || url.match?(%r{\Ahttps://[^/?#]*@}i)

      uri.host.to_s.match?(CERTIFICATE_HOST) && uri.path.end_with?(".pem")
    rescue URI::Error
      false
    end

    def self.canonical_string(message)
      fields = SIGNABLE_FIELDS.fetch(message["Type"])
      fields.filter_map { |field| "#{field}\n#{message[field]}\n" unless message[field].nil? }.join
    end

    def self.signing_certificate(url)
      # Serialize misses for the same URL without holding the cache lock during I/O.
      DOWNLOAD_LOCKS[url.hash % CACHE_LIMIT].synchronize do
        cached = CACHE_LOCK.synchronize { @certificates[url] }
        cached || cache_certificate(url, download_certificate(url))
      end
    end

    def self.cache_certificate(url, certificate)
      CACHE_LOCK.synchronize do
        @certificates.shift if @certificates.size >= CACHE_LIMIT
        @certificates[url] = certificate
      end
    end

    def self.download_certificate(url)
      body = MessageApis::SafeDownload.fetch(url, max_bytes: 64 * 1024, max_redirects: 0, deadline: 5)
      raise CertificateUnavailable unless body

      pem = body.read[/-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----/m] || reject!
      OpenSSL::X509::Certificate.new(pem)
    rescue OpenSSL::X509::CertificateError
      reject!
    end

    def self.certificate_current?(certificate) = Time.current.between?(certificate.not_before, certificate.not_after)

    def self.valid_signature?(key, digest, signature, data)
      key.is_a?(OpenSSL::PKey::RSA) && key.verify(digest, signature, data)
    end

    def self.reject! = raise(VerificationError, "invalid SNS message signature")

    private_class_method :precheck!, :valid_string?, :nonempty_string?, :single_line?,
                         :cache_certificate, :valid_signature?, :reject!
  end
end
