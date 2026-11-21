# frozen_string_literal: true

require "rails_helper"

RSpec.describe Lead do
  let(:app) { FactoryBot.create(:app) }

  def create_lead(attrs)
    visitor = app.add_anonymous_user({})
    visitor.update!(attrs)
    visitor.become_lead!
    Lead.find(visitor.id)
  end

  it "copies the lead's country and moves the conversation to the matching user" do
    app.add_user(email: "other@test.cl")
    user = app.add_user(email: "a@test.cl", country: "chile")
    lead = create_lead(email: "a@test.cl", country: "peru")
    conversation = app.start_conversation(message: { text_content: "hi" }, from: lead)

    lead.verify!

    expect(user.reload.country).to eq("peru")
    expect(conversation.reload.main_participant_id).to eq(user.id)
    expect(lead.events.where(action: "leads.verified").count).to eq(1)
  end

  it "converts a lead without an email even when another user has no email" do
    app.add_anonymous_user({}).update_column(:type, "AppUser")
    lead = create_lead({})

    lead.verify!

    expect(AppUser.find(lead.id).type).to eq("AppUser")
    expect(lead.events.where(action: "leads.verified")).to be_empty
  end
end
