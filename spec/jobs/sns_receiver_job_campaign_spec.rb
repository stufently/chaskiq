# frozen_string_literal: true

require "rails_helper"

RSpec.describe SnsReceiverJob do
  let(:app) { FactoryBot.create(:app) }
  let(:agent) { app.add_agent({ email: "agent@test.cl", first_name: "Agent" }).agent }
  let(:user) { app.add_user(email: "user@test.cl", first_name: "User") }
  let(:campaign) { app.campaigns.create(name: "Test Campaign", subject: "Test") }

  it "tracks a click for a campaign notification" do
    allow(Campaign).to receive(:find_by).with(id: "7").and_return(campaign)
    allow(AppUser).to receive(:find_by).with(id: "9").and_return(user)

    message = {
      "mail" => {
        "headers" => [
          { "name" => "X-CHASKIQ-CAMPAIGN-ID", "value" => "7" },
          { "name" => "X-CHASKIQ-CAMPAIGN-TO", "value" => "9" }
        ]
      },
      "click" => { "ipAddress" => "1.2.3.4" }
    }

    expect(user).to receive(:track_click).with(
      host: "1.2.3.4",
      trackable: campaign,
      data: { "ipAddress" => "1.2.3.4" }
    )

    described_class.new.perform("click", message, "https://ref.example")
  end
end
