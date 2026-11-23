# frozen_string_literal: true

require "rails_helper"

RSpec.describe UserHandler do
  let(:app) { FactoryBot.create(:app, custom_fields: [{ "name" => "plan" }]) }

  it "updates an existing user and stores only configured properties" do
    email = "member@example.test"
    first = app.add_user(email: email, first_name: "Before", plan: "free")
    visited_at = Time.zone.local(2025, 1, 2, 3)

    updated = app.add_user(
      email: email, first_name: "After", plan: "paid", unknown: "discard", last_visited_at: visited_at
    )

    expect(updated.id).to eq(first.id)
    expect(updated.reload).to have_attributes(
      type: "AppUser", first_name: "After", last_visited_at: visited_at, email: email
    )
    expect(updated.properties).to include("plan" => "paid")
    expect(updated.properties).not_to have_key("unknown")
    expect(updated).to be_subscribed
  end

  it "keeps a lead separate and updates it by email" do
    email = "lead@example.test"
    lead = app.add_lead(email: email, first_name: "Before", plan: "trial")
    original_session = lead.session_id

    updated = app.add_lead(email: email, first_name: "After", plan: "active")

    expect(updated.id).to eq(lead.id)
    expect(updated.reload).to have_attributes(type: "Lead", email: email, first_name: "After")
    expect(updated.properties).to include("plan" => "active")
    expect(updated.session_id).to be_present
    expect(updated.session_id).not_to eq(original_session)
  end

  it "finds a visitor by its current session and rotates the session token" do
    visitor = app.add_anonymous_user(session_id: "incoming", properties: { name: "Visitor One" })
    original_session = visitor.session_id

    updated = app.add_anonymous_user(session_id: original_session, properties: { name: "Visitor Two" })

    expect(updated.id).to eq(visitor.id)
    expect(updated.reload).to have_attributes(type: "Visitor", name: "Visitor Two")
    expect(updated.session_id).to be_present
    expect(updated.session_id).not_to eq(original_session)
  end

  it "raises the original error when visitor callbacks are disabled" do
    expect do
      app.add_anonymous_user(session_id: "incoming", disable_callbacks: true)
    end.to raise_error(NameError, /app_user/)
  end

  it "creates bot and admin roles against the same app" do
    bot_role = app.add_bot_agent({ email: "assistant@example.test", name: "Helper" })
    admin_role = app.add_admin(email: "admin@example.test", password: "test-password")

    expect(bot_role.reload.agent).to be_bot
    expect(app.agents).to include(bot_role.agent)
    expect(admin_role.reload).to have_attributes(role: "admin", access_list: ["manage"])
    expect(app.agents).to include(admin_role.agent)
  end
end
