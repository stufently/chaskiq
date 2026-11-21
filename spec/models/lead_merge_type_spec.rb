# frozen_string_literal: true

require "rails_helper"

RSpec.describe Lead do
  let(:app) { FactoryBot.create(:app) }

  it "does not overwrite the target user type on merge" do
    visitor = app.add_anonymous_user({})
    visitor.update!(email: "a@test.cl", country: "peru")
    visitor.become_lead!
    lead = Lead.find(visitor.id)

    user = app.add_user(email: "b@test.cl", country: "chile")
    user.update_column(:email, "a@test.cl")

    lead.verify!

    expect(user.reload.type).to eq("AppUser")
    expect(user.country).to eq("peru")
    expect(AppUser.find(lead.id).type).to eq("Lead")

    Lead.find(lead.id).verify!

    expect(user.reload.type).to eq("AppUser")
    expect(AppUser.find(lead.id).type).to eq("Lead")
    expect(lead.events.where(action: "leads.verified").count).to eq(2)
  end
end
