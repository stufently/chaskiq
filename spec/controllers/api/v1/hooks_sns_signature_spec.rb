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
  let(:message_id) { SecureRandom.uuid }
  let(:topic) { "arn:aws:sns:us-east-1:123456789012:events" }

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
      "MessageId" => message_id,
      "Timestamp" => "2026-11-19T10:00:00Z",
      "TopicArn" => topic
    }
  end

  def confirmation(type = "SubscriptionConfirmation", url: subscribe_url)
    notification.merge("Type" => type, "SubscribeURL" => url, "Token" => "test")
  end

  def signed(message, version: "2")
    fields = %w[Message MessageId Timestamp TopicArn Type]
    fields = %w[Message MessageId SubscribeURL Timestamp Token TopicArn Type] if message["Type"] != "Notification"
    input = fields.map { |field| "#{field}\n#{message.fetch(field)}\n" }.join
    digest = version == "1" ? "SHA1" : "SHA256"
    signature = Base64.strict_encode64(key.sign(digest, input))
    message.merge("Signature" => signature, "SignatureVersion" => version, "SigningCertURL" => cert_url)
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
    ENV["SNS_ALLOWED_TOPIC_ARNS"] = " #{topic} "
    cert = serve_certificate
    subscribe = stub_request(:get, subscribe_url)

    deliver(signed(confirmation, version: "1"))

    expect(response).to have_http_status(:ok)
    assert_requested(cert, times: 1)
    assert_requested(subscribe, times: 1)
    expect(SnsReceiverJob).not_to have_received(:perform_later)
  end

  it "confirms a signed POST without Content-Type after its input has been read" do
    ENV["SNS_ALLOWED_TOPIC_ARNS"] = topic
    serve_certificate
    subscribe = stub_request(:get, subscribe_url)
    input = StringIO.new(signed(confirmation).to_json)
    app = lambda do |env|
      expect(env).not_to have_key("CONTENT_TYPE")
      # Model a parameter parser that consumed the input and cached its result.
      env.fetch("rack.input").read
      env["rack.request.form_input"] = env.fetch("rack.input")
      env["rack.request.form_hash"] = {}
      Rails.application.call(env)
    end

    result = Rack::MockRequest.new(app).post("/api/v1/hooks", input: input)

    expect(result.status).to eq(200)
    assert_requested(subscribe, times: 1)
  end

  it "rejects a signed confirmation with an empty allowlist and logs the required setting" do
    ENV["SNS_ALLOWED_TOPIC_ARNS"] = " , "
    allow(Rails.logger).to receive(:warn).and_call_original
    subscribe = stub_request(:get, subscribe_url)

    deliver(signed(confirmation))

    expect(response).to have_http_status(:forbidden)
    expect(Rails.logger).to have_received(:warn).with("set SNS_ALLOWED_TOPIC_ARNS to confirm #{topic}").once
    assert_not_requested(subscribe)
    expect(MessageApis::SafeDownload).not_to have_received(:resolve)
  end

  it "does not request a foreign SubscribeURL even for an allowlisted topic" do
    ENV["SNS_ALLOWED_TOPIC_ARNS"] = topic
    cert = serve_certificate
    foreign_url = "https://sns.us-east-1.amazonaws.com.example.test/confirm"
    subscribe = stub_request(:get, foreign_url)

    deliver(signed(confirmation(url: foreign_url)))

    expect(response).to have_http_status(:ok)
    assert_requested(cert, times: 1)
    assert_not_requested(subscribe)
  end

  it "does not request SubscribeURL on sns.s3.amazonaws.com" do
    ENV["SNS_ALLOWED_TOPIC_ARNS"] = topic
    cert = serve_certificate
    url = "https://sns.s3.amazonaws.com/confirm"
    subscribe = stub_request(:get, url)

    deliver(signed(confirmation(url: url)))

    expect(response).to have_http_status(:ok)
    assert_requested(cert, times: 1)
    assert_not_requested(subscribe)
  end

  it "returns 503 when an allowed SubscribeURL fails and retries the confirmation" do
    ENV["SNS_ALLOWED_TOPIC_ARNS"] = topic
    serve_certificate
    subscribe = stub_request(:get, subscribe_url).to_return({ status: 500 }, { status: 200 })
    message = signed(confirmation)

    deliver(message)
    expect(response).to have_http_status(:service_unavailable)
    deliver(message)
    expect(response).to have_http_status(:ok)
    assert_requested(subscribe, times: 2)
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

  it "deduplicates a verified Notification by MessageId for 24 hours" do
    serve_certificate
    message = signed(notification)
    key = "sns:notification:#{message_id}"

    deliver(message)
    expect(response).to have_http_status(:ok)
    deliver(message)
    expect(response).to have_http_status(:ok)

    expect(SnsReceiverJob).to have_received(:perform_later).once
    ttl = Redis::Objects.redis.with { |redis| redis.ttl(key) }
    expect(ttl).to be_between(1.day.to_i - 5, 1.day.to_i)
  end

  it "releases the Notification MessageId when handling fails so a retry can proceed" do
    serve_certificate
    message = signed(notification)
    key = "sns:notification:#{message_id}"
    allow(SnsReceiverJob).to receive(:perform_later) do
      expect(Redis::Objects.redis.with { |redis| redis.get(key) }).to be_present
      raise "queue unavailable"
    end
    expect { deliver(message) }.to raise_error(RuntimeError, "queue unavailable")
    expect(Redis::Objects.redis.with { |redis| redis.get(key) }).to be_nil

    allow(SnsReceiverJob).to receive(:perform_later).and_return(true)
    deliver(message)

    expect(response).to have_http_status(:ok)
    expect(SnsReceiverJob).to have_received(:perform_later).twice
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

  it "rejects subscription confirmation URLs with non-standard ports" do
    ENV["SNS_ALLOWED_TOPIC_ARNS"] = topic
    serve_certificate
    bad_port_url = "https://sns.us-east-1.amazonaws.com:8443/confirm"
    subscribe = stub_request(:get, bad_port_url)
    deliver(signed(confirmation.merge("SubscribeURL" => bad_port_url)))

    assert_not_requested(subscribe)
  end

  it "rejects subscription confirmation URLs with userinfo" do
    ENV["SNS_ALLOWED_TOPIC_ARNS"] = topic
    serve_certificate
    userinfo_url = "https://user@sns.us-east-1.amazonaws.com/confirm"
    subscribe = stub_request(:get, userinfo_url)
    deliver(signed(confirmation.merge("SubscribeURL" => userinfo_url)))

    assert_not_requested(subscribe)
  end
end
