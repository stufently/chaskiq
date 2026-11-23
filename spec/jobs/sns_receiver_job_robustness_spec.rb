# frozen_string_literal: true

require "rails_helper"

RSpec.describe SnsReceiverJob do
  let(:app) { FactoryBot.create(:app) }
  let(:user) { app.add_user(email: "reader@example.com") }
  let(:campaign) { FactoryBot.create(:campaign, app: app) }
  let(:job) { described_class.new }

  def campaign_headers
    [
      { "name" => "X-CHASKIQ-CAMPAIGN-ID", "value" => campaign.id.to_s },
      { "name" => "X-CHASKIQ-CAMPAIGN-TO", "value" => user.id.to_s }
    ]
  end

  describe "SES send events for campaigns" do
    # SesSenderJob records the send in the transaction that delivers the
    # message; an SNS "send" event can arrive before that commits, so it must
    # never write a send of its own.
    it "does not record a send when SesSenderJob has not committed one yet" do
      message = { "mail" => { "headers" => campaign_headers }, "send" => {} }

      expect { job.perform("send", message, nil) }.not_to(change { campaign.metrics.where(action: "send").count })
    end

    it "still records a delivery event" do
      message = { "mail" => { "headers" => campaign_headers }, "delivery" => {} }

      expect { job.perform("delivery", message, nil) }
        .to change { campaign.metrics.where(action: "delivery", app_user: user).count }.by(1)
    end
  end

  describe "notifications without original headers" do
    it "processes a permanent bounce without mail headers" do
      message = {
        "mail" => { "messageId" => "abc" },
        "bounce" => { "bounceType" => "Permanent", "bouncedRecipients" => [{ "emailAddress" => user.email }] }
      }

      expect { job.perform("bounce", message, nil) }.not_to raise_error
      expect(user.reload).to be_subscribed
    end

    it "processes a complaint without mail headers" do
      message = {
        "mail" => {},
        "complaint" => { "complainedRecipients" => [{ "emailAddress" => user.email }] }
      }

      expect { job.perform("complaint", message, nil) }.not_to raise_error
    end

    it "ignores a campaign event without a recipient header" do
      message = {
        "mail" => { "headers" => [{ "name" => "X-CHASKIQ-CAMPAIGN-ID", "value" => campaign.id.to_s }] },
        "open" => { "ipAddress" => "203.0.113.1" }
      }

      expect { job.perform("open", message, nil) }.not_to(change(Metric, :count))
    end

    it "ignores a conversation open without a Return-Path header" do
      message = {
        "mail" => { "headers" => [{ "name" => "X-CHASKIQ-PART-ID", "value" => "1" }] },
        "open" => {}
      }

      expect { job.perform("open", message, nil) }.not_to raise_error
    end
  end
end
