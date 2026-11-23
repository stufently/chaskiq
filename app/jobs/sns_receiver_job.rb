# frozen_string_literal: true

class SnsReceiverJob < ApplicationJob
  queue_as :default

  # Receive hook. SES may be configured without original headers, so every
  # header lookup is nil-safe and a notification without the Chaskiq headers
  # is skipped instead of raising (and retrying forever).
  def perform(track_type, m, referrer)
    part_id = header_value(m, "X-CHASKIQ-PART-ID")
    campaign_id = header_value(m, "X-CHASKIQ-CAMPAIGN-ID")

    # handle conversation and exit
    handle_chat_message(track_type, m, part_id) if part_id.present?

    # handle campaign
    handle_campaign_message(track_type, m, referrer) if campaign_id.present?

    unsubscribe_user(track_type, m)
  end

  def handle_campaign_message(track_type, m, _referrer)
    # SesSenderJob records the send in the transaction that delivers the
    # message; this event can arrive before that commits, so recording it here
    # would duplicate the send.
    return if track_type == "send"

    data = m[track_type]
    campaign_id = header_value(m, "X-CHASKIQ-CAMPAIGN-ID")
    user_id = header_value(m, "X-CHASKIQ-CAMPAIGN-TO")
    return if campaign_id.blank? || user_id.blank?

    campaign = Campaign.find_by(id: campaign_id)
    app_user = AppUser.find_by(id: user_id)

    return if campaign.blank? || app_user.blank?

    app_user.send(:"track_#{track_type}",
                  host: data&.dig("ipAddress"),
                  trackable: campaign,
                  data: data)
  end

  def handle_chat_message(track_type, m, part_id)
    return unless track_type == "open"

    recipient = header_value(m, "Return-Path")
    return if recipient.blank?

    recipient_parts = URLcrypt.decode(recipient.split("@").first.split("+").last)
    _, conversation_id = recipient_parts.split("+")

    conversation = Conversation.find_by(id: conversation_id)
    return if conversation.blank?

    message = conversation.messages.find(part_id)
    return if message.blank?

    message.read! unless message.read?
  end

  private

  def unsubscribe_user(track_type, m)
    case track_type
    when "complaint"
      get_app_user_from_email(m, "complaint", "complainedRecipients")
      true
    when "bounce"
      return unless m.dig("bounce", "bounceType") == "Permanent"

      get_app_user_from_email(m, "bounce", "bouncedRecipients")
    end
  end

  # Unsubscribes the recipients only inside the app that sent the message: the
  # same address can be a contact of other apps that never mailed it. A
  # notification without a Chaskiq campaign or conversation header names no
  # app, so nobody is unsubscribed. Contacts that cannot be unsubscribed
  # (already unsubscribed) are skipped, so a repeated notification is a no-op.
  def get_app_user_from_email(message, message_type, type_kind)
    emails = Array(message.dig(message_type, type_kind)).pluck("emailAddress").compact
    return if emails.empty?

    app = app_for_notification(message)
    if app.blank?
      Rails.logger.warn("SnsReceiverJob: #{message_type} for an unknown app, nobody unsubscribed")
      return
    end

    app.app_users.where(email: emails).find_each do |user|
      user.unsubscribe! if user.may_unsubscribe?
    end
  end

  def app_for_notification(message)
    campaign_id = header_value(message, "X-CHASKIQ-CAMPAIGN-ID")
    return Campaign.find_by(id: campaign_id)&.app if campaign_id.present?

    part_id = header_value(message, "X-CHASKIQ-PART-ID")
    ConversationPart.find_by(id: part_id)&.conversation&.app if part_id.present?
  end

  def header_value(message, name)
    Array(message.dig("mail", "headers")).find { |o| o["name"] == name }&.dig("value")
  end

  def parsed_message_id(m)
    header_value(m, "Message-ID").to_s.split("@").first&.delete("<")
  end

  def get_email_from_notification(m)
    m.dig("mail", "commonHeaders", "to")
  end
end
