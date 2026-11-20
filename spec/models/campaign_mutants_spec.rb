# frozen_string_literal: true

require "rails_helper"

RSpec.describe Campaign, type: :model do
  let(:app) { FactoryBot.create(:app) }
  let(:campaign) { FactoryBot.create(:campaign, app: app) }

  describe ".decode_email" do
    it "uses the app key from the address when another app was created first" do
      FactoryBot.create(:app)
      encoded = described_class.encode_email("#{campaign.app.key}-#{campaign.id}")

      expect(described_class.decode_email("campaigns+#{encoded}@example.com")).to eq(campaign)
    end
  end

  describe "#mustache_template_for" do
    let(:host) { "https://mail.example.com" }
    let(:subscriber) { app.add_user(email: "subscriber@example.com") }

    before do
      allow(Rails.application.routes).to receive(:default_url_options).and_return({ host: host })
    end

    it "renders custom subscriber properties" do
      subscriber.update!(properties: { "plan" => "pro" })

      expect(campaign.mustache_template_for(subscriber, html: "{{plan}}")).to eq("pro")
    end

    it "renders explicit HTML when a premailer template is stored" do
      campaign.update_column(:premailer, "Stored template")

      expect(campaign.mustache_template_for(subscriber, html: "<p>Explicit template</p>"))
        .to eq("<p>Explicit template</p>")
    end

    it "renders the unsubscribe URL for the campaign and subscriber" do
      rendered = campaign.mustache_template_for(subscriber, html: "{{campaign_unsubscribe}}")

      expect(rendered).to eq("#{host}/campaigns/#{campaign.id}/subscribers/#{subscriber.encoded_id}/delete")
    end
  end
end
