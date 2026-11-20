# frozen_string_literal: true

require "rails_helper"

RSpec.describe Campaign, type: :model do
  let(:app) { FactoryBot.create(:app) }
  let(:campaign) { FactoryBot.create(:campaign, app: app) }

  before do
    allow(Rails.application.routes).to receive(:default_url_options).and_return({ host: "https://mail.example.com" })
  end

  describe "#campaign_url" do
    it "returns full campaign url" do
      expect(campaign.campaign_url).to eq("https://mail.example.com/campaigns/#{campaign.id}")
    end
  end

  describe "#campaign_api_url" do
    it "returns full campaign api url" do
      expect(campaign.campaign_api_url).to eq("https://mail.example.com/api/v1/apps/#{app.key}/messages/#{campaign.id}")
    end
  end

  describe ".decode_email" do
    it "decodes a valid campaign email back to the campaign" do
      encoded = Campaign.encode_email("#{app.key}-#{campaign.id}")
      result = Campaign.decode_email("campaigns+#{encoded}@x")
      expect(result).to eq(campaign)
    end

    it "returns nil for non-existent id" do
      encoded = Campaign.encode_email("#{app.key}-999999")
      result = Campaign.decode_email("campaigns+#{encoded}@x")
      expect(result).to be_nil
    end

    it "returns nil for address without +" do
      result = Campaign.decode_email("campaigns@example.com")
      expect(result).to be_nil
    end
  end

  describe "#mustache_template_for" do
    it "renders mustache template with email and campaign_url" do
      subscriber = app.add_user(email: "sub@test.cl")
      result = campaign.mustache_template_for(subscriber, html: "<p>{{email}} %7B%7Bcampaign_url%7D%7D</p>")
      expect(result).to include("sub@test.cl")
      expect(result).to include(campaign.campaign_url)
    end
  end
end
