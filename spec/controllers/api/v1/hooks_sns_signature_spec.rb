# frozen_string_literal: true

require "rails_helper"
require "webmock"

RSpec.describe Api::V1::HooksController, type: :controller do
  include WebMock::API

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
    allow(MessageApis::SafeDownload).to receive(:resolve).and_return(["54.239.1.1"])
    allow(SnsReceiverJob).to receive(:perform_later)
  end

  def self.signing_key
    @signing_key ||= OpenSSL::PKey::RSA.new(2048)
  end

  let(:key) { self.class.signing_key }
  let(:cert_url) { "https://sns.us-east-1.amazonaws.com/controller-test-#{SecureRandom.hex(8)}.pem" }
  let(:subscribe_url) { "https://sns.us-east-1.amazonaws.com/?Action=ConfirmSubscription&Token=test" }
  let(:event) { { "eventType" => "Open" } }

  let(:certificate_pem) do
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 1
    cert.subject = cert.issuer = OpenSSL::X509::Name.parse("/CN=SNS test")
    cert.public_key = key.public_key
    cert.not_before = 1.hour.ago
    cert.not_after = 1.hour.from_now
    cert.sign(key, "SHA256")
    cert.to_pem
  end

  def notification
    {
      "Type" => "Notification",
      "Message" => event.to_json,
      "MessageId" => "test-id",
      "Timestamp" => "2026-11-19T10:00:00Z",
      "TopicArn" => "arn:aws:sns:us-east-1:123456789012:events"
    }
  end

  def confirmation(type = "SubscriptionConfirmation", url: subscribe_url)
    notification.merge("Type" => type, "SubscribeURL" => url, "Token" => "test")
  end

  def signed(message)
    fields = %w[Message MessageId Timestamp TopicArn Type]
    fields = %w[Message MessageId SubscribeURL Timestamp Token TopicArn Type] if message["Type"] != "Notification"
    input = fields.map { |field| "#{field}\n#{message.fetch(field)}\n" }.join
    signature = Base64.strict_encode64(key.sign("SHA256", input))
    message.merge("Signature" => signature, "SignatureVersion" => "2", "SigningCertURL" => cert_url)
  end

  def deliver(message, header: nil)
    request.headers["x-amz-sns-message-type"] = header if header
    post :create, body: message.to_json
  end

  def serve_certificate
    stub_request(:get, cert_url).to_return(body: certificate_pem)
  end

  it "rejects an unsigned confirmation before requesting SubscribeURL" do
    subscribe = stub_request(:get, subscribe_url)

    deliver(confirmation, header: "SubscriptionConfirmation")

    expect(response).to have_http_status(:forbidden)
    expect(response.body).to eq("invalid SNS message signature")
    assert_not_requested(subscribe)
    expect(MessageApis::SafeDownload).not_to have_received(:resolve)
  end

  it "rejects a tampered Message without enqueuing the event" do
    serve_certificate
    deliver(signed(notification).merge("Message" => { "eventType" => "Bounce" }.to_json))

    expect(response).to have_http_status(:forbidden)
    expect(SnsReceiverJob).not_to have_received(:perform_later)
  end

  it "routes a signed Notification by Type even with a SubscriptionConfirmation header" do
    serve_certificate
    subscribe = stub_request(:get, subscribe_url)

    deliver(signed(notification.merge("SubscribeURL" => subscribe_url)), header: "SubscriptionConfirmation")

    expect(response).to have_http_status(:ok)
    assert_not_requested(subscribe)
    expect(SnsReceiverJob).to have_received(:perform_later).with("open", event, anything).once
  end

  it "returns 503 for a temporary certificate outage and succeeds on retry" do
    stub_request(:get, cert_url).to_return({ status: 500 }, { body: certificate_pem })
    message = signed(notification)

    deliver(message)
    expect(response).to have_http_status(:service_unavailable)
    expect(response.body).to eq("SNS signing certificate unavailable")
    expect(SnsReceiverJob).not_to have_received(:perform_later)

    deliver(message)
    expect(response).to have_http_status(:ok)
    expect(SnsReceiverJob).to have_received(:perform_later).with("open", event, anything).once
  end

  it "requests SubscribeURL after verifying a signed SubscriptionConfirmation" do
    cert = serve_certificate
    subscribe = stub_request(:get, subscribe_url)

    deliver(signed(confirmation))

    expect(response).to have_http_status(:ok)
    assert_requested(cert, times: 1)
    assert_requested(subscribe, times: 1)
    expect(SnsReceiverJob).not_to have_received(:perform_later)
  end

  it "verifies a signed Notification and enqueues the event" do
    cert = serve_certificate

    deliver(signed(notification))

    expect(response).to have_http_status(:ok)
    assert_requested(cert, times: 1)
    expect(SnsReceiverJob).to have_received(:perform_later).with("open", event, anything).once
  end

  it "acknowledges a verified UnsubscribeConfirmation without confirming or enqueuing" do
    cert = serve_certificate
    subscribe = stub_request(:get, subscribe_url)

    deliver(signed(confirmation("UnsubscribeConfirmation")), header: "Notification")

    expect(response).to have_http_status(:ok)
    assert_requested(cert, times: 1)
    assert_not_requested(subscribe)
    expect(SnsReceiverJob).not_to have_received(:perform_later)
  end

  it "returns 400 for malformed JSON" do
    post :create, body: "{"

    expect(response).to have_http_status(:bad_request)
    expect(response.body).to eq("bad request")
    expect(MessageApis::SafeDownload).not_to have_received(:resolve)
  end

  it "returns 400 for JSON that is not an object" do
    deliver([])

    expect(response).to have_http_status(:bad_request)
    expect(response.body).to eq("bad request")
    expect(MessageApis::SafeDownload).not_to have_received(:resolve)
  end
end
