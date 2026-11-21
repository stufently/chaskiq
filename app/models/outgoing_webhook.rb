# frozen_string_literal: true

class OutgoingWebhook < ApplicationRecord
  belongs_to :app

  validates :url, presence: true

  acts_as_taggable

  def send_verification; end

  def send_notification(data: {})
    service = OutgoingWebhookService.new(url: url)
    service.send_post(data)
  end

  def enabled?
    state == "enabled"
  end
  alias is_enabled enabled?

  def as_json(*)
    super.tap do |hash|
      hash["enabled"] = is_enabled
    end
  end
end
