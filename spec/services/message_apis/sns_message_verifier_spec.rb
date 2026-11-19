# frozen_string_literal: true

require "rails_helper"
require "webmock"

RSpec.describe "MessageApis::SnsMessageVerifier" do
  include WebMock::API
  include ActiveSupport::Testing::TimeHelpers

  around do |example|
    original_topics = ENV.delete("SNS_ALLOWED_TOPIC_ARNS")
    WebMock.enable!
    example.run
  ensure
    ENV["SNS_ALLOWED_TOPIC_ARNS"] = original_topics
    WebMock.reset!
    WebMock.disable!
  end

  before do
    verifier.clear_cache!
    allow(MessageApis::SafeDownload).to receive(:resolve).and_return(["54.239.1.1"])
  end

  def self.signing_key
    @signing_key ||= OpenSSL::PKey::RSA.new(2048)
  end

  let(:verifier) { MessageApis::SnsMessageVerifier }
  let(:key) { self.class.signing_key }
  let(:topic) { "arn:aws:sns:us-east-1:123456789012:events" }
  let(:cert_url) { "https://sns.us-east-1.amazonaws.com/signing.pem" }
  let(:expires_at) { 1.hour.from_now.change(usec: 0) }

  let(:certificate) do
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 1
    cert.subject = cert.issuer = OpenSSL::X509::Name.parse("/CN=SNS test")
    cert.public_key = key.public_key
    cert.not_before = 1.hour.ago
    cert.not_after = expires_at
    cert.sign(key, "SHA256")
    cert
  end

  let(:notification) do
    {
      "Type" => "Notification",
      "Message" => "Hello\nworld",
      "MessageId" => "test-id",
      "Timestamp" => "2026-11-19T10:00:00Z",
      "TopicArn" => topic
    }
  end

  def signed(message = notification, version: "2", digest: "SHA256", url: cert_url)
    signature = Base64.strict_encode64(key.sign(digest, signing_input(message)))
    message.merge("Signature" => signature, "SignatureVersion" => version, "SigningCertURL" => url)
  end

  def signing_input(message)
    fields = %w[Message MessageId Subject Timestamp TopicArn Type]
    fields = %w[Message MessageId SubscribeURL Timestamp Token TopicArn Type] if message["Type"] != "Notification"
    fields.filter_map { |field| "#{field}\n#{message.fetch(field)}\n" if message.key?(field) }.join
  end

  def serve_certificate(body: certificate.to_pem, url: cert_url)
    stub_request(:get, url).to_return(body: body)
  end

  def expect_rejected_without_dns(message)
    expect { verifier.verify!(message) }.to raise_error(verifier::VerificationError)
    expect(MessageApis::SafeDownload).not_to have_received(:resolve)
  end

  def matching_old_lock_url(url)
    (1..).lazy.map { |id| "https://sns.us-east-1.amazonaws.com/other-#{id}.pem" }
         .find { |candidate| candidate.hash % 32 == url.hash % 32 }
  end

  def hold_certificate_download(url, started, release)
    pem = certificate.to_pem
    stub_request(:get, url).to_return do
      started << true
      release.pop
      { body: pem }
    end.then.to_return(body: pem)
  end

  it "includes Subject in the Notification signature" do
    serve_certificate
    message = signed(notification.merge("Subject" => "SES event"))

    expect(verifier.verify!(message)).to be(true)
    expect { verifier.verify!(message.merge("Subject" => "Changed")) }.to raise_error(verifier::VerificationError)
  end

  it "rejects a signed field containing a newline before DNS" do
    expect_rejected_without_dns(signed(notification.merge("Subject" => "two\nlines")))
    expect_rejected_without_dns(signed(notification.merge("MessageId" => "carriage\rreturn")))
  end

  it "verifies SignatureVersion 1 with SHA1 and SignatureVersion 2 with SHA256" do
    serve_certificate

    expect(verifier.verify!(signed(version: "1", digest: "SHA1"))).to be(true)
    expect(verifier.verify!(signed)).to be(true)
    expect { verifier.verify!(signed(version: "1")) }.to raise_error(verifier::VerificationError)
    expect { verifier.verify!(signed(digest: "SHA1")) }.to raise_error(verifier::VerificationError)
  end

  it "rejects an unsupported SignatureVersion before DNS" do
    expect_rejected_without_dns(signed(version: "3"))
  end

  it "restricts SigningCertURL to HTTPS SNS certificate endpoints before DNS" do
    urls = %w[
      https://s3.us-east-1.amazonaws.com/signing.pem
      https://sns.us-east-1.amazonaws.com.example.test/signing.pem
      http://sns.us-east-1.amazonaws.com/signing.pem
      https://sns.us-east-1.amazonaws.com:444/signing.pem
      https://user@sns.us-east-1.amazonaws.com/signing.pem
      https://@sns.us-east-1.amazonaws.com/signing.pem
      https://sns.us-east-1.amazonaws.com/signing.pem?
      https://sns.us-east-1.amazonaws.com/signing.pem#
      https://sns.us-east-1.amazonaws.com/signing.pem.txt
    ]
    urls.each { |url| expect_rejected_without_dns(signed(url: url)) }
  end

  it "accepts SigningCertURL for standard, China, and GovCloud regions" do
    %w[us-east-1.amazonaws.com cn-north-1.amazonaws.com.cn us-gov-west-1.amazonaws.com].each do |region|
      url = "https://sns.#{region}/signing.pem"
      serve_certificate(url: url)
      expect(verifier.verify!(signed(url: url))).to be(true)
    end
  end

  it "rejects a SigningCertURL whose region is an S3 or arbitrary label" do
    %w[s3 s3-external-1 evil].each do |region|
      expect_rejected_without_dns(signed(url: "https://sns.#{region}.amazonaws.com/signing.pem"))
    end
  end

  it "reports a certificate redirect as a temporary failure without following it" do
    target = "https://sns.us-east-2.amazonaws.com/redirected.pem"
    stub_request(:get, cert_url).to_return(status: 302, headers: { "Location" => target })
    redirected = serve_certificate(url: target)

    expect { verifier.verify!(signed) }.to raise_error(verifier::CertificateUnavailable)
    assert_not_requested(redirected)
  end

  it "accepts 64 KiB of certificate data" do
    serve_certificate(body: certificate.to_pem.ljust(64 * 1024))

    expect(verifier.verify!(signed)).to be(true)
  end

  it "rejects certificate data one byte over 64 KiB as unavailable" do
    serve_certificate(body: certificate.to_pem.ljust((64 * 1024) + 1))

    expect { verifier.verify!(signed) }.to raise_error(verifier::CertificateUnavailable)
  end

  it "sets an actual SafeDownload timeout of at most 5 seconds" do
    serve_certificate
    allow(Timeout).to receive(:timeout).and_call_original

    expect(verifier.verify!(signed)).to be(true)
    expect(Timeout).to have_received(:timeout).with(be <= 5)
    expect(Timeout).not_to have_received(:timeout).with(be > 5)
  end

  it "uses the cache after loading a certificate once" do
    request = serve_certificate

    2.times { expect(verifier.verify!(signed)).to be(true) }
    assert_requested(request, times: 1)
  end

  it "uses one cache entry for normalized SigningCertURL host and port" do
    request = serve_certificate
    expect(verifier.verify!(signed)).to be(true)
    expect(verifier.verify!(signed(url: "HTTPS://SNS.US-EAST-1.AMAZONAWS.COM:443/signing.pem"))).to be(true)
    assert_requested(request, times: 1)
  end

  it "keeps the working cache entry when an invalid signature would exceed capacity" do
    request = serve_certificate
    message = signed
    expect(verifier.verify!(message)).to be(true)
    31.times do |id|
      url = "https://sns.us-east-1.amazonaws.com/valid-#{id}.pem"
      serve_certificate(url: url)
      expect(verifier.verify!(signed(url: url))).to be(true)
    end

    url = "https://sns.us-east-1.amazonaws.com/unverified.pem"
    serve_certificate(url: url)
    invalid = signed(url: url).merge("Message" => "Changed")
    expect { verifier.verify!(invalid) }.to raise_error(verifier::VerificationError)
    expect(verifier.verify!(message)).to be(true)
    assert_requested(request, times: 1)
  end

  it "does not cache a certificate already past its not_after" do
    expired = certificate.dup
    expired.not_after = 5.minutes.ago
    expired.sign(key, "SHA256")
    stub_request(:get, cert_url).to_return({ body: expired.to_pem }, { body: certificate.to_pem })
    message = signed

    expect { verifier.verify!(message) }.to raise_error(verifier::VerificationError)
    expect(verifier.verify!(message)).to be(true)
  end

  it "bounds the lock wait for the same certificate URL to 5 seconds" do
    started = Queue.new
    release = Queue.new
    allow(Timeout).to receive(:timeout).and_call_original
    allow(Timeout).to receive(:timeout).with(5).and_yield
    hold_certificate_download(cert_url, started, release)
    message = signed
    download = Thread.new { verifier.verify!(message) }

    Timeout.timeout(2) { started.pop }
    expect { Timeout.timeout(7) { verifier.verify!(message) } }.to raise_error(verifier::CertificateUnavailable)
  ensure
    release << true
    download&.value
  end

  it "does not block cached or new certificates for different exact URLs" do
    started = Queue.new
    release = Queue.new
    other_url = matching_old_lock_url(cert_url)
    serve_certificate(url: other_url)
    other_message = signed(url: other_url)
    hold_certificate_download(cert_url, started, release)
    message = signed
    download = Thread.new { verifier.verify!(message) }

    Timeout.timeout(2) { started.pop }
    expect(Timeout.timeout(2) { verifier.verify!(other_message) }).to be(true)
    expect(Timeout.timeout(2) { verifier.verify!(other_message) }).to be(true)
  ensure
    release << true
    download&.value
  end

  it "reports a temporary certificate outage and retries the same URL successfully" do
    request = stub_request(:get, cert_url).to_return({ status: 500 }, { body: certificate.to_pem })
    message = signed

    expect { verifier.verify!(message) }.to raise_error(verifier::CertificateUnavailable)
    expect(verifier.verify!(message)).to be(true)
    assert_requested(request, times: 2)
  end

  it "allows only exact TopicArn matches when the allowlist is configured" do
    ENV["SNS_ALLOWED_TOPIC_ARNS"] = " , #{topic}, #{topic}-second , "
    expect_rejected_without_dns(signed(notification.merge("TopicArn" => "#{topic}-other")))
    serve_certificate
    expect(verifier.verify!(signed)).to be(true)
    expect(verifier.verify!(signed(notification.merge("TopicArn" => "#{topic}-second")))).to be(true)
  end

  it "allows any TopicArn with an empty allowlist and warns once" do
    ENV["SNS_ALLOWED_TOPIC_ARNS"] = " , , "
    serve_certificate
    allow(Rails.logger).to receive(:warn).and_call_original

    expect(verifier.verify!(signed)).to be(true)
    expect(verifier.verify!(signed(notification.merge("TopicArn" => "#{topic}-other")))).to be(true)
    expect(Rails.logger).to have_received(:warn).with(/SNS_ALLOWED_TOPIC_ARNS/).once
  end

  it "rejects invalid Base64 and out-of-range signature lengths before DNS" do
    message = signed
    expect_rejected_without_dns(message.merge("Signature" => "#{message.fetch('Signature')}!"))
    [127, 1025].each do |length|
      expect_rejected_without_dns(message.merge("Signature" => Base64.strict_encode64("a" * length)))
    end
  end

  it "rejects a Notification missing its required MessageId before DNS" do
    message = notification.except("MessageId")
    expect_rejected_without_dns(signed(message))
  end

  it "rejects a confirmation missing its required Token before DNS" do
    message = notification.merge(
      "Type" => "SubscriptionConfirmation",
      "SubscribeURL" => "https://sns.us-east-1.amazonaws.com/?Action=ConfirmSubscription"
    )
    expect_rejected_without_dns(signed(message))
  end

  it "rejects a cached certificate after not_after without fetching it again" do
    request = serve_certificate
    message = signed
    expect(verifier.verify!(message)).to be(true)

    travel_to(expires_at + 1.second) do
      expect { verifier.verify!(message) }.to raise_error(verifier::VerificationError)
    end
    assert_requested(request, times: 1)
  end
end
