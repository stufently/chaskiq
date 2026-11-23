# frozen_string_literal: true

require "rails_helper"

RSpec.describe SnsReceiverJob do
  let(:app) { FactoryBot.create(:app) }
  let(:user) { app.add_user(email: "reader@example.com") }
  let(:job) { described_class.new }
  let(:recipient_header) { { "name" => "X-CHASKIQ-CAMPAIGN-TO", "value" => user.id.to_s } }

  def click_notification(headers)
    {
      "mail" => { "headers" => headers },
      "click" => { "ipAddress" => "203.0.113.10" }
    }
  end

  def bounce_notification(bounce_type)
    campaign = FactoryBot.create(:campaign, app: app)
    {
      "mail" => {
        "headers" => [{ "name" => "X-CHASKIQ-CAMPAIGN-ID", "value" => campaign.id.to_s }, recipient_header]
      },
      "bounce" => {
        "bounceType" => bounce_type,
        "bouncedRecipients" => [{ "emailAddress" => user.email }]
      }
    }
  end

  it "skips click tracking when the notification references a missing campaign" do
    campaign_header = { "name" => "X-CHASKIQ-CAMPAIGN-ID", "value" => "0" }
    allow(AppUser).to receive(:find_by).with(id: user.id.to_s).and_return(user)
    allow(user).to receive(:track_click)

    job.perform("click", click_notification([campaign_header, recipient_header]), nil)

    expect(user).not_to have_received(:track_click)
  end

  it "ignores a click notification with only a campaign recipient header" do
    allow(AppUser).to receive(:find_by).with(id: user.id.to_s).and_return(user)
    allow(user).to receive(:track_click)

    expect do
      job.perform("click", click_notification([recipient_header]), nil)
    end.not_to raise_error

    expect(user).not_to have_received(:track_click)
  end

  it "unsubscribes the recipient of a permanent bounce" do
    expect do
      job.perform("bounce", bounce_notification("Permanent"), nil)
    end.to change { user.reload.subscription_state }.from("subscribed").to("unsubscribed")
  end

  it "keeps the recipient of a transient bounce subscribed" do
    job.perform("bounce", bounce_notification("Transient"), nil)

    expect(user.reload).to be_subscribed
  end
end
