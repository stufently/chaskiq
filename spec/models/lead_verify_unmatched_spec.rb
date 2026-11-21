# frozen_string_literal: true

require "rails_helper"

RSpec.describe Lead do
  it "converts the lead when the matching email belongs to a user in another app" do
    app = FactoryBot.create(:app)
    other_app = FactoryBot.create(:app)
    foreign = other_app.add_user(email: "a@test.cl")
    visitor = app.add_anonymous_user({})
    visitor.update!(email: "a@test.cl")
    visitor.become_lead!
    lead = Lead.find(visitor.id)

    expect { lead.verify! }.not_to raise_error
    expect(AppUser.find(lead.id).type).to eq("AppUser")
    expect(foreign.reload.app_id).to eq(other_app.id)
  end
end
