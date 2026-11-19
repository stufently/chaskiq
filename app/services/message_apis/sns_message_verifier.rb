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
    CERTIFICATE_HOST = /\Asns\.[a-z]{2}(-gov|-iso[a-z]?)?-[a-z]+-\d+\.amazonaws\.com(\.cn)?\z/i
    TOPIC_LOCK = Mutex.new

    # Protects verified certificates and bounds the registry of pending downloads.
    class CertificateCache
      CAPACITY = 32
      LOCK_TIMEOUT = 5
      Download = Struct.new(:mutex, :users)

      def initialize
        @certificates = {}
        @downloads = {}
        @guard = Mutex.new
      end

      def clear
        @guard.synchronize { @certificates.clear }
      end

      def fetch_verified(url, verify)
        certificate = fetch(url)
        return verify.call(certificate) if certificate

        with_download_lock(url) do
          certificate = fetch(url)
          return verify.call(certificate) if certificate

          certificate = yield
          verify.call(certificate)
          store(url, certificate)
        end
      end

      private

      def fetch(url)
        @guard.synchronize { @certificates[url] }
      end

      def store(url, certificate)
        @guard.synchronize do
          @certificates.shift if @certificates.size >= CAPACITY
          @certificates[url] = certificate
        end
      end

      def with_download_lock(url)
        download = reserve(url)
        acquire(download.mutex)
        begin
          yield
        ensure
          download.mutex.unlock
        end
      ensure
        release(url, download) if download
      end

      def reserve(url)
        @guard.synchronize do
          download = @downloads[url]
          raise CertificateUnavailable if !download && @downloads.size >= CAPACITY

          download ||= @downloads[url] = Download.new(Mutex.new, 0)
          download.users += 1
          download
        end
      end

      def release(url, download)
        @guard.synchronize do
          download.users -= 1
          @downloads.delete(url) if download.users.zero?
        end
      end

      def acquire(mutex)
        deadline = monotonic_time + LOCK_TIMEOUT
        loop do
          remaining = deadline - monotonic_time
          raise CertificateUnavailable unless remaining.positive?
          return if mutex.try_lock

          sleep([0.01, remaining].min)
        end
      end

      def monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end

    CERTIFICATES = CertificateCache.new
    private_constant :CertificateCache, :CERTIFICATES

    def self.verify!(message)
      digest, signature, url = precheck!(message)
      signing_certificate(url) do |certificate|
        reject! unless certificate_current?(certificate)

        valid_signature?(certificate.public_key, digest, signature, canonical_string(message)) || reject!
      end
      true
    rescue OpenSSL::OpenSSLError
      reject!
    end

    def self.clear_cache!
      CERTIFICATES.clear
      TOPIC_LOCK.synchronize { @warned_about_topics = false }
    end

    def self.precheck!(message)
      reject! unless message.is_a?(Hash) && SIGNABLE_FIELDS.key?(message["Type"])

      validate_fields!(message)
      digest = digest_for(message["SignatureVersion"]) || reject!
      signature = decode_signature(message["Signature"])
      reject! unless topic_allowed?(message)

      [digest, signature, normalized_certificate_url(message["SigningCertURL"])]
    end

    def self.normalized_certificate_url(url)
      reject! unless certificate_url?(url)

      URI.parse(url).normalize.to_s
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

    def self.topic_allowed?(message)
      arn = message["TopicArn"]
      allowed = ENV.fetch("SNS_ALLOWED_TOPIC_ARNS", "").split(",").map(&:strip).reject(&:empty?)
      return allowed.include?(arn) unless allowed.empty?
      return warn_open_topics unless message["Type"] == "SubscriptionConfirmation"

      Rails.logger.warn("set SNS_ALLOWED_TOPIC_ARNS to confirm #{arn}")
      false
    end

    def self.warn_open_topics
      TOPIC_LOCK.synchronize do
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

    def self.signing_certificate(url, &verify)
      CERTIFICATES.fetch_verified(url, verify) { download_certificate(url) }
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
                         :warn_open_topics, :normalized_certificate_url, :valid_signature?, :reject!
  end
end
