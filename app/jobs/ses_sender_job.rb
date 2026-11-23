# frozen_string_literal: true

require "zlib"

class SesSenderJob < ApplicationJob
  queue_as :mailers

  # send to ses, at most once per campaign and recipient: the advisory lock
  # serialises duplicate jobs for the same pair and the "send" metric written
  # in the same transaction marks the recipient as done.
  def perform(campaign, subscription)
    return if subscription.blank? || subscription.unsubscribed?

    Metric.transaction do
      lock_delivery(campaign, subscription)
      next if campaign.delivered_to?(subscription)

      campaign.prepare_mail_to(subscription).deliver_now
      subscription.track_send(trackable: campaign)
    end
  end

  private

  def lock_delivery(campaign, subscription)
    key = Zlib.crc32("campaign-delivery:#{campaign.id}:#{subscription.id}")
    Metric.connection.select_value("SELECT pg_advisory_xact_lock(#{key.to_i})")
  end
end
