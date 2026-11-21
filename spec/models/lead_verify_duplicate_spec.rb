# frozen_string_literal: true

require "rails_helper"

RSpec.describe Lead do
  let(:app) { FactoryBot.create(:app) }

  it "merges into the oldest user when several share the email" do
    older = app.add_user(email: "one@test.cl", country: "chile")
    newer = app.add_user(email: "two@test.cl", country: "chile")
    newer.update_column(:email, "a@test.cl")
    older.update_column(:email, "a@test.cl")

    visitor = app.add_anonymous_user({})
    visitor.update!(email: "a@test.cl", country: "peru")
    visitor.become_lead!
    lead = Lead.find(visitor.id)

    conversation = app.start_conversation(message: { text_content: "hi" }, from: lead)

    lead.verify!

    expect(older.reload.country).to eq("peru")
    expect(newer.reload.country).to eq("chile")
    expect(conversation.reload.main_participant_id).to eq(older.id)
  end
end
