# frozen_string_literal: true

# Probe for fork-updates-m10: every SNS message posted to /api/v1/hooks is verified before use.
# Run (P=docs/specs/fork-updates-m10-probes): bash $P/rspec_gate_m10.sh --only $P/m10_probe_spec.rb
# Leaf certificate issued by a locally generated CA (no chain check: SNS serves only the leaf),
# webmock for HTTP, SafeDownload.resolve stubbed: no network.
require "rails_helper"
require "webmock"

# Metrics/BlockLength: probe spec; spec/** is excluded the same way in .rubocop.yml.
# rubocop:disable-next Metrics/BlockLength
RSpec.describe Api::V1::HooksController, type: :controller do
  include WebMock::API
  include ActiveSupport::Testing::TimeHelpers

  around do |example|
    WebMock.enable!
    example.run
  ensure
    WebMock.reset!
    WebMock.disable!
  end

  def self.rsa(name)
    @rsa ||= {}
    @rsa[name] ||= OpenSSL::PKey::RSA.new(2048)
  end

  def self.x509(subject, key, signer: nil, is_ca: false, valid: 1.minute.ago..1.day.from_now)
    issuer, issuer_key = signer
    cert = blank_cert(subject, key, valid)
    cert.issuer = issuer ? issuer.subject : cert.subject
    add_extensions(cert, issuer || cert, is_ca)
    cert.sign(issuer_key || key, "SHA256")
  end

  def self.blank_cert(subject, key, valid)
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = rand(1..(2**31))
    cert.subject = OpenSSL::X509::Name.parse(subject)
    cert.public_key = key.public_key
    cert.not_before = valid.begin
    cert.not_after = valid.end
    cert
  end

  def self.add_extensions(cert, issuer, is_ca)
    factory = OpenSSL::X509::ExtensionFactory.new(issuer, cert)
    cert.add_extension(factory.create_extension("basicConstraints", is_ca ? "CA:TRUE" : "CA:FALSE", true))
    cert.add_extension(factory.create_extension("keyUsage", is_ca ? "keyCertSign,cRLSign" : "digitalSignature", true))
  end

  def self.ca
    @ca ||= x509("/CN=Local Test CA", rsa(:ca), is_ca: true, valid: 1.day.ago..1.year.from_now)
  end

  def self.leaf(key = rsa(:leaf), valid: 1.minute.ago..1.day.from_now)
    x509("/CN=sns.amazonaws.com", key, signer: [ca, rsa(:ca)], valid: valid)
  end

  def self.leaf_pem
    @leaf_pem ||= leaf.to_pem
  end

  let(:key) { self.class.rsa(:leaf) }
  let(:topic) { "arn:aws:sns:us-east-1:123456789012:chaskiq" }
  let(:cert_url) { "https://sns.us-east-1.amazonaws.com/SimpleNotificationService-#{SecureRandom.hex(16)}.pem" }
  let(:subscribe_url) { "https://sns.us-east-1.amazonaws.com/?Action=ConfirmSubscription&Token=#{SecureRandom.hex(8)}" }
  let!(:any_request) { stub_request(:any, /.*/).to_return(status: 200, body: "") }

  before do
    MessageApis::SnsMessageVerifier.clear_cache!
    allow(MessageApis::SafeDownload).to receive(:resolve).and_return(["54.239.1.1"])
    allow(SnsReceiverJob).to receive(:perform_later)
    ENV.delete("SNS_ALLOWED_TOPIC_ARNS")
  end

  after { ENV.delete("SNS_ALLOWED_TOPIC_ARNS") }

  def serve_cert(url = cert_url, pem: self.class.leaf_pem)
    stub_request(:get, url).to_return(status: 200, body: pem, headers: { "Content-Type" => "application/x-pem-file" })
  end

  def signable_keys(type)
    return %w[Message MessageId Subject Timestamp TopicArn Type] if type == "Notification"

    %w[Message MessageId SubscribeURL Timestamp Token TopicArn Type]
  end

  def canonical(msg)
    signable_keys(msg["Type"]).filter_map { |k| "#{k}\n#{msg[k]}\n" unless msg[k].nil? }.join
  end

  def sign(msg, version: "2", digest: nil, with: key, url: cert_url)
    digest ||= version == "1" ? "SHA1" : "SHA256"
    msg = msg.merge("SignatureVersion" => version, "SigningCertURL" => url)
    msg.merge("Signature" => Base64.strict_encode64(with.sign(digest, canonical(msg))))
  end

  def ses_open_event
    { "eventType" => "Open", "mail" => { "headers" => [{ "name" => "X-CHASKIQ-PART-ID", "value" => "1" }] },
      "open" => { "ipAddress" => "1.2.3.4" } }.to_json
  end

  def notification(extra = {})
    { "Type" => "Notification", "MessageId" => SecureRandom.uuid, "TopicArn" => topic, "Message" => ses_open_event,
      "Timestamp" => "2026-11-19T10:00:00.000Z" }.merge(extra)
  end

  def confirmation(type = "SubscriptionConfirmation", url: subscribe_url)
    { "Type" => type, "MessageId" => SecureRandom.uuid, "Token" => SecureRandom.hex(16), "TopicArn" => topic,
      "Message" => "You have chosen to subscribe to the topic.\nTo confirm, visit the SubscribeURL.",
      "SubscribeURL" => url, "Timestamp" => "2026-11-19T10:00:00.000Z" }
  end

  def deliver(body, header: nil)
    request.headers["x-amz-sns-message-type"] = header || body["Type"] if body.is_a?(Hash)
    post :create, body: body.is_a?(String) ? body : body.to_json
    response
  end

  def allow_topics(value)
    ENV["SNS_ALLOWED_TOPIC_ARNS"] = value
  end

  # rubocop:disable-next Metrics/BlockLength
  describe "valid messages" do
    it "confirms a signed SubscriptionConfirmation with SignatureVersion 1 (SHA1)" do
      cert = serve_cert
      confirm = stub_request(:get, subscribe_url).to_return(status: 200, body: "<xml/>")
      expect(deliver(sign(confirmation, version: "1")).status).to eq(200)
      assert_requested(cert, times: 1)
      assert_requested(confirm, times: 1)
    end

    it "accepts a signed Notification with SignatureVersion 2 (SHA256) and enqueues the SES event" do
      serve_cert
      expect(deliver(sign(notification)).status).to eq(200)
      expect(SnsReceiverJob).to have_received(:perform_later).once
    end

    it "verifies the Subject of a signed Notification" do
      serve_cert
      signed = sign(notification("Subject" => "Amazon SES event"))
      expect(deliver(signed).status).to eq(200)
      expect(deliver(signed.merge("Subject" => "Other subject")).status).to eq(403)
      expect(SnsReceiverJob).to have_received(:perform_later).once
    end

    it "accepts a signing certificate from sns.<region>.amazonaws.com.cn" do
      cn = "https://sns.cn-north-1.amazonaws.com.cn/SimpleNotificationService-#{SecureRandom.hex(8)}.pem"
      serve_cert(cn)
      expect(deliver(sign(notification, url: cn)).status).to eq(200)
    end

    it "acknowledges a signed UnsubscribeConfirmation without any request besides the certificate" do
      cert = serve_cert
      confirm = stub_request(:get, subscribe_url)
      expect(deliver(sign(confirmation("UnsubscribeConfirmation"))).status).to eq(200)
      assert_requested(cert, times: 1)
      assert_not_requested(confirm)
      expect(SnsReceiverJob).not_to have_received(:perform_later)
    end

    it "keeps the SubscribeURL host check for a signed SubscriptionConfirmation" do
      serve_cert
      foreign = "https://sns.us-east-1.amazonaws.com.example.com/confirm"
      outbound = stub_request(:get, foreign)
      expect(deliver(sign(confirmation(url: foreign))).status).to eq(200)
      assert_not_requested(outbound)
    end
  end

  # rubocop:disable-next Metrics/BlockLength
  describe "rejected messages" do
    it "rejects a tampered Message with 403 and acts on nothing" do
      serve_cert
      confirm = stub_request(:get, subscribe_url)
      expect(deliver(sign(confirmation).merge("Message" => "changed")).status).to eq(403)
      assert_not_requested(confirm)
      expect(deliver(sign(notification).merge("Message" => ses_open_event.sub("Open", "Click"))).status).to eq(403)
      expect(SnsReceiverJob).not_to have_received(:perform_later)
    end

    it "rejects an unsigned SubscriptionConfirmation without any request" do
      expect(deliver(confirmation).status).to eq(403)
      unsigned = { "notificationType" => "AmazonSnsSubscriptionSucceeded", "SubscribeURL" => subscribe_url }
      expect(deliver(unsigned, header: "SubscriptionConfirmation").status).to eq(403)
      expect(deliver(notification).status).to eq(403)
      assert_not_requested(any_request)
      expect(SnsReceiverJob).not_to have_received(:perform_later)
    end

    it "rejects a message without a required field before any network access" do
      expect(MessageApis::SafeDownload).not_to receive(:fetch)
      %w[Message MessageId Timestamp TopicArn Signature SignatureVersion SigningCertURL].each do |field|
        expect(deliver(sign(notification).except(field)).status).to eq(403), field
      end
      %w[SubscribeURL Token].each do |field|
        expect(deliver(sign(confirmation).except(field)).status).to eq(403), field
      end
    end

    it "rejects a broken Base64 or short signature before any network access" do
      expect(MessageApis::SafeDownload).not_to receive(:fetch)
      expect(deliver(sign(notification).merge("Signature" => "not base64 at all!")).status).to eq(403)
      expect(deliver(sign(notification).merge("Signature" => Base64.strict_encode64("x" * 32))).status).to eq(403)
    end

    it "rejects an unknown SignatureVersion and a digest that does not match SignatureVersion" do
      serve_cert
      expect(deliver(sign(notification, version: "3", digest: "SHA256")).status).to eq(403)
      expect(deliver(sign(notification, version: "2", digest: "SHA1")).status).to eq(403)
      expect(deliver(sign(notification, version: "1", digest: "SHA256")).status).to eq(403)
      expect(SnsReceiverJob).not_to have_received(:perform_later)
    end

    it "rejects a signature made by another key" do
      serve_cert
      expect(deliver(sign(notification, with: self.class.rsa(:other))).status).to eq(403)
      expect(SnsReceiverJob).not_to have_received(:perform_later)
    end

    it "fetches the SigningCertURL only from https sns.<region>.amazonaws.com(.cn) .pem URLs" do
      %w[
        http://sns.us-east-1.amazonaws.com/a.pem
        https://sns.us-east-1.amazonaws.com.evil.example/a.pem
        https://evil.example/sns.us-east-1.amazonaws.com/a.pem
        https://user@sns.us-east-1.amazonaws.com/a.pem
        https://sns.us-east-1.amazonaws.com:8443/a.pem
        https://sns.us-east-1.amazonaws.com/a.txt
        https://sns.us-east-1.amazonaws.com/a.pem?x=1
        https://s3.amazonaws.com/a.pem
        https://xsns.us-east-1.amazonaws.com/a.pem
      ].each do |url|
        expect(deliver(sign(notification, url: url)).status).to eq(403), url
      end
      assert_not_requested(any_request)
    end

    it "rejects an expired or not yet valid certificate" do
      serve_cert(pem: self.class.leaf(valid: 2.days.ago..1.day.ago).to_pem)
      expect(deliver(sign(notification)).status).to eq(403)
      later = "https://sns.us-east-1.amazonaws.com/SimpleNotificationService-later.pem"
      serve_cert(later, pem: self.class.leaf(valid: 1.day.from_now..2.days.from_now).to_pem)
      expect(deliver(sign(notification, url: later)).status).to eq(403)
      expect(SnsReceiverJob).not_to have_received(:perform_later)
    end

    it "stops trusting a cached certificate after its not_after" do
      cert = serve_cert(pem: self.class.leaf(valid: 1.minute.ago..1.hour.from_now).to_pem)
      expect(deliver(sign(notification)).status).to eq(200)
      travel_to(2.hours.from_now) { expect(deliver(sign(notification)).status).to eq(403) }
      assert_requested(cert, times: 1)
    end

    it "rejects a newline in a signed field other than Message" do
      serve_cert
      expect(deliver(sign(notification("Subject" => "a\nTopicArn\nb"))).status).to eq(403)
      expect(SnsReceiverJob).not_to have_received(:perform_later)
    end

    it "returns 400 for a body that is not a JSON object" do
      expect(deliver("not json").status).to eq(400)
      expect(deliver("[1,2]").status).to eq(400)
    end
  end

  describe "TopicArn allowlist" do
    it "accepts only listed topics when SNS_ALLOWED_TOPIC_ARNS is set, before any network access" do
      allow_topics(" arn:aws:sns:us-east-1:1:other , #{topic}")
      serve_cert
      expect(deliver(sign(notification)).status).to eq(200)
      allow_topics("arn:aws:sns:us-east-1:1:other")
      expect(MessageApis::SafeDownload).not_to receive(:fetch)
      expect(deliver(sign(notification)).status).to eq(403)
      expect(deliver(sign(notification("TopicArn" => "#{topic}x"))).status).to eq(403)
    end

    it "accepts any topic without SNS_ALLOWED_TOPIC_ARNS and warns once" do
      serve_cert
      allow(Rails.logger).to receive(:warn).and_call_original
      2.times { expect(deliver(sign(notification("TopicArn" => "arn:aws:sns:eu-west-1:9:any"))).status).to eq(200) }
      expect(Rails.logger).to have_received(:warn).with(/SNS_ALLOWED_TOPIC_ARNS/).once
    end
  end

  describe "certificate download" do
    it "answers 503 on a temporary certificate failure and does not cache it" do
      responses = [{ status: 500, body: "" }, { status: 200, body: self.class.leaf_pem }]
      cert = stub_request(:get, cert_url).to_return(*responses)
      expect(deliver(sign(notification)).status).to eq(503)
      expect(SnsReceiverJob).not_to have_received(:perform_later)
      expect(deliver(sign(notification)).status).to eq(200)
      assert_requested(cert, times: 2)
    end

    it "answers 503 when the certificate host does not resolve" do
      allow(MessageApis::SafeDownload).to receive(:resolve).and_return([])
      expect(deliver(sign(notification)).status).to eq(503)
    end

    it "fetches the certificate with no redirects, 64 KiB and at most 5 seconds" do
      serve_cert
      allow(Timeout).to receive(:timeout).and_call_original
      expect(MessageApis::SafeDownload).to receive(:fetch)
        .with(cert_url, hash_including(max_bytes: 64 * 1024, max_redirects: 0, deadline: be <= 5))
        .and_call_original
      expect(deliver(sign(notification)).status).to eq(200)
      expect(Timeout).to have_received(:timeout).with(be <= 5).at_least(:once)
      expect(Timeout).not_to have_received(:timeout).with(be > 5)
    end

    it "does not follow a redirect for the signing certificate" do
      target = "https://sns.us-west-2.amazonaws.com/SimpleNotificationService-target.pem"
      stub_request(:get, cert_url).to_return(status: 302, headers: { "Location" => target })
      moved = serve_cert(target)
      expect(deliver(sign(notification)).status).to eq(503)
      assert_not_requested(moved)
      expect(SnsReceiverJob).not_to have_received(:perform_later)
    end

    it "accepts a certificate of exactly 64 KiB and rejects one byte more" do
      pem = self.class.leaf_pem
      serve_cert(pem: pem + ("#" * ((64 * 1024) - pem.bytesize)))
      expect(deliver(sign(notification)).status).to eq(200)
      big = "https://sns.us-east-1.amazonaws.com/SimpleNotificationService-big.pem"
      serve_cert(big, pem: pem + ("#" * ((64 * 1024) - pem.bytesize + 1)))
      expect(deliver(sign(notification, url: big)).status).to eq(503)
    end

    it "downloads one signing certificate once for several messages" do
      cert = serve_cert
      3.times { expect(deliver(sign(notification)).status).to eq(200) }
      assert_requested(cert, times: 1)
    end
  end

  describe "decisions" do
    it "decides by the signed Type, not by the x-amz-sns-message-type header" do
      serve_cert
      confirm = stub_request(:get, subscribe_url)
      signed = sign(notification).merge("SubscribeURL" => subscribe_url)
      expect(deliver(signed, header: "SubscriptionConfirmation").status).to eq(200)
      assert_not_requested(confirm)
      expect(SnsReceiverJob).to have_received(:perform_later).once
    end
  end
end
