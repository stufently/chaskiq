# frozen_string_literal: true

require "rails_helper"

RSpec.describe SnsReceiverJob do
  let(:app) { FactoryBot.create(:app) }
  # Create a dummy campaign first to ensure campaign and app_user have different IDs
  let!(:dummy_campaign) { FactoryBot.create(:campaign, app: app) }
  let(:campaign) { FactoryBot.create(:campaign, app: app) }
  let(:app_user) { app.add_user(email: "user@example.com") }

  let(:headers) do
    [
      { "name" => "X-CHASKIQ-CAMPAIGN-ID", "value" => campaign.id.to_s },
      { "name" => "X-CHASKIQ-CAMPAIGN-TO", "value" => app_user.id.to_s },
      { "name" => "X-Other", "value" => "other" }
    ]
  end

  let(:message) do
    {
      "mail" => { "headers" => headers },
      "click" => { "ipAddress" => "1.2.3.4" }
    }
  end

  describe "handle_campaign_message with both headers" do
    it "creates a click metric for the correct campaign and user" do
      expect do
        described_class.new.perform("click", message, nil)
      end.to change(Metric, :count).by(1)

      metric = Metric.last
      expect(metric.action).to eq("click")
      expect(metric.host).to eq("1.2.3.4")
      expect(metric.trackable).to eq(campaign)
      expect(metric.app_user).to eq(app_user)
    end
  end

  describe "handle_campaign_message with only CAMPAIGN-TO" do
    let(:headers) do
      [
        { "name" => "X-CHASKIQ-CAMPAIGN-TO", "value" => app_user.id.to_s }
      ]
    end

    it "does not call track_click when CAMPAIGN-ID header is missing" do
      expect_any_instance_of(AppUser).not_to receive(:track_click)
      described_class.new.perform("click", message, nil)
    end
  end

  describe "handle_campaign_message with only CAMPAIGN-ID" do
    let(:headers) do
      [
        { "name" => "X-CHASKIQ-CAMPAIGN-ID", "value" => campaign.id.to_s }
      ]
    end

    it "ignores the event when CAMPAIGN-TO header is missing" do
      expect { described_class.new.perform("click", message, nil) }.not_to(change(Metric, :count))
    end
  end
end
