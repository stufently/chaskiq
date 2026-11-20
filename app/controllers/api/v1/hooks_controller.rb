# frozen_string_literal: true

require "uri"

class Api::V1::HooksController < ActionController::API
  include MessageApis::Helpers
  include ActionView::Helpers::SanitizeHelper

  before_action :verify_sns_message
  before_action :check_aws_confirmation
  before_action :handle_notification, if: :is_notification_message?

  def create
    render(plain: "ok")
  end

  private

  def handle_notification
    key = "sns:notification:#{@request_body.fetch('MessageId')}"
    token = SecureRandom.uuid
    return render(plain: "ok") unless reserve_notification(key, token)

    begin
      process_notification
    rescue StandardError
      release_notification(key, token)
      raise
    end
    render(plain: "ok")
  end

  def reserve_notification(key, token)
    Redis::Objects.redis.with { |redis| redis.set(key, token, nx: true, ex: 1.day.to_i) }
  end

  def release_notification(key, token)
    Redis::Objects.redis.with do |redis|
      redis.eval(<<~LUA, keys: [key], argv: [token])
        if redis.call("GET", KEYS[1]) == ARGV[1] then
          return redis.call("DEL", KEYS[1])
        end
      LUA
    end
  end

  def process_notification
    if @request_body["Subject"] == "Amazon SES Email Receipt Notification"
      process_email_notification(@request_body["Message"])
    elsif @request_body["Message"] != "Successfully validated SNS topic for Amazon SES event publishing."
      process_event_notification
    end
  end

  def verify_sns_message
    @request_body = JSON.parse(request.raw_post.to_s)
    return render(plain: "bad request", status: :bad_request) unless @request_body.is_a?(Hash)

    MessageApis::SnsMessageVerifier.verify!(@request_body)
  rescue JSON::ParserError
    render(plain: "bad request", status: :bad_request)
  rescue MessageApis::SnsMessageVerifier::VerificationError
    render(plain: "invalid SNS message signature", status: :forbidden)
  rescue MessageApis::SnsMessageVerifier::CertificateUnavailable
    render(plain: "SNS signing certificate unavailable", status: :service_unavailable)
  end

  def check_aws_confirmation
    return unless @request_body["Type"] == "SubscriptionConfirmation"

    send_subscription_confirmation
    render(plain: "ok") unless performed?
  end

  def is_notification_message?
    @request_body["Type"] == "Notification"
  end

  # TODO: add some tests mdfk!
  def process_email_notification(message)
    json_message = JSON.parse(message)
    json_message["receipt"]
    json_message["mail"]["headers"].map { |o| { o["name"] => o["value"] } }
    json_message["receipt"]["action"]
    action = json_message["receipt"]["action"]

    mail_body = read_mail_file(action)
    mail       = Mail.read_from_string(mail_body)
    from       = mail.from
    to         = mail.to
    recipients = mail.recipients # ["messages+aaa@hermessenger.com"] de aqui sale el app y el mensaje!

    mail.part # will convert plain into multipart
    # EmailReplyParser.parse_reply(mail.text_part.body.to_s)
    # message = EmailReplyParser.parse_reply(mail.text_part.body.to_s).gsub("\n", "<br/>").force_encoding(Encoding::UTF_8)
    body = mail&.text_part&.body&.to_s&.force_encoding(Encoding::UTF_8)

    return if body.blank?
    return if recipients.empty?

    text = EmailReplyTrimmer.trim(body)
    message = text.gsub("\n", "<br/>")

    app, conversation, from = handle_conversation_part(mail, json_message)

    messageId = json_message["mail"]["messageId"]
    # for now just skip the message
    return if from.blank?

    message = process_attachments(mail, message)

    serialized_content = begin
      serialize_content(message)
    rescue StandardError
      nil
    end

    opts = {
      from: from,
      message: {
        serialized_content: serialized_content || text_block(text),
        html_content: message
      },
      email_message_id: mail.message_id
    }

    conversation.add_message(opts)
  end

  def track_message_for(track_type, m)
    SnsReceiverJob.perform_later(track_type, m, request.remote_ip)
  end

  def send_subscription_confirmation
    subscribe_url = @request_body["SubscribeURL"]
    return unless subscribe_url.is_a?(String)

    uri = URI.parse(subscribe_url)
    return unless uri.is_a?(URI::HTTPS) && uri.port == 443 && uri.userinfo.nil?
    return unless uri.host&.match?(MessageApis::SnsMessageVerifier::CERTIFICATE_HOST)

    return if MessageApis::SafeDownload.fetch(subscribe_url, max_redirects: 0)

    render(plain: "SNS subscription confirmation unavailable", status: :service_unavailable)
  rescue URI::Error
    nil
  end

  def find_resources_in_recipient_parts(recipient_parts)
    app_id, conversation_id = recipient_parts.split("+")
    app = App.find(app_id)
    conversation = app.conversations.find(conversation_id)
    [app, conversation]
  end

  def decode_inbound_address(address)
    app, role = App.decode_inbound_address(address)
  end

  def read_mail_file(action)
    file = AWS_CLIENT.get_object(
      bucket: action["bucketName"],
      key: action["objectKey"]
    )
    file.body.read
  end

  def handle_direct_upload(attachment)
    file = StringIO.new(attachment.decoded)
    direct_upload(
      file: file,
      filename: attachment.filename,
      content_type: attachment.mime_type
    )
  end

  def find_remitent(app:, from:)
    app.agents.find_by(email: from.first) || app.app_users.find_by(email: from.first)
  end

  def serialize_content(message)
    serialize_content_from_html(message)
  end

  def handle_message_recipient(mail)
    recipient = mail.recipients.first
    recipient_parts = URLcrypt.decode(recipient.split("@").first.split("+").last)
    app, conversation = find_resources_in_recipient_parts(recipient_parts)
    # this logic implies that if the email.from correspond to an agent , then we assume that the message is from agent
    from = find_remitent(app: app, from: mail.from)
    # TODO: handle blank author with a conversation.add_message_event
    # to notify that the email was not delivered, which is the mos probable case
    # but whe should inspect the status of this
    # we have found notification like this:
    #  ""An error occurred while trying to deliver the mail to the following recipients:<br/>miguel@chaskiq.io""
    [app, conversation, from]
  end

  def handle_inbound_recipient(mail)
    recipient = mail.recipients.first
    app, agent = decode_inbound_address(recipient)
    return if app.blank?
    return unless app&.plan&.enabled?("InboundEmails")

    create_conversation_from_incoming(app, mail)
  end

  def handle_inbound_recipient_from_forwarded(mail, val)
    app, agent = decode_inbound_address(val)
    return if app.blank?
    return unless app&.plan&.enabled?("InboundEmails")

    create_conversation_from_incoming(app, mail)
  end

  def handle_campaigns_recipient(mail)
    recipient = mail.recipients.first
    campaign = Campaign.decode_email(recipient)
    return if campaign.nil?

    app = campaign.app
    create_conversation_from_incoming(app, mail)
  end

  def handle_conversation_part(mail, json_message)
    recipient = mail.recipients.first
    if recipient.starts_with?("messages+")
      handle_message_recipient(mail)
    elsif recipient.starts_with?("inbound+")
      handle_inbound_recipient(mail)
    elsif recipient.starts_with?("campaigns+")
      handle_campaigns_recipient(mail)
    elsif (val = json_message["mail"]["headers"].find { |o| o["name"] == "X-Forwarded-To" }&.dig("value")) && val.present? && val.starts_with?("inbound+")
      handle_inbound_recipient_from_forwarded(mail, val)
    end
  end

  def create_conversation_from_incoming(app, mail)
    conversation = app.conversation_parts.find_by(email_message_id: mail.message_id)&.conversation
    if conversation.blank?
      mail_from = mail.from.first
      app_user = app.app_users.find_by(email: mail_from) ||
                 app.add_user(email: mail_from, name: mail[:from]&.formatted)
      from = app_user
      conversation = app.start_conversation(from: from, subject: mail.subject)
    end
    [app, conversation, from]
  end

  def process_attachments(mail, message)
    mail.attachments.each do |attachment|
      next unless attachment.content_type.start_with?("image/")

      message = process_attachment(attachment, message)
    end
    message
  end

  def process_attachment(attachment, message)
    uploaded_data = handle_direct_upload(attachment)
    attachment_string_pattern = "[image: #{attachment.filename}]"
    image_mark = "<img src='#{uploaded_data[:url]}' title='#{attachment.filename}' width='#{uploaded_data[:width]}' height='#{uploaded_data[:height]}' />"

    # replace for inline attachments or append for attachments
    if message.include?(attachment_string_pattern)
      message.gsub!(
        attachment_string_pattern,
        image_mark
      )
    else
      message = image_mark.dup << message
    end
  end

  def process_event_notification
    message = parse_body_message(@request_body["Message"])
    return if message.blank?
    return if message["eventType"].blank?

    track_message_for(message["eventType"].downcase, message)
  end

  def parse_body_message(body)
    JSON.parse(body)
  rescue StandardError
    nil
  end
end
