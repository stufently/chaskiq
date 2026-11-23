# frozen_string_literal: true

class MailSenderJob < ApplicationJob
  queue_as :default

  # send to all list with state passive & subscribed
  # A retry after a partial failure skips the recipients that already got the
  # campaign (SesSenderJob records a "send" metric per delivered recipient).
  def perform(campaign)
    return if campaign.state == "sent"

    campaign.apply_premailer
    delivered = campaign.metrics.where(action: "send").select(:app_user_id)
    campaign
      .available_segments
      .where.not(email: nil)
      .where.not(id: delivered)
      .find_each do |app_user|
      campaign.push_notification(app_user)
    end

    campaign.state = "sent"
    campaign.save
    campaign.broadcast_event
  end
end
