# frozen_string_literal: true

require "rails_helper"

RSpec.describe AppUserDashboard do
  it "counts the user's conversations by state and labels missing states as unknown" do
    app = FactoryBot.create(:app)
    user = app.add_user(email: "dashboard@example.com")
    other_user = app.add_user(email: "other-dashboard@example.com")
    3.times { app.conversations.create!(main_participant: user) }
    2.times { app.conversations.create!(main_participant: user, state: "closed") }
    app.conversations.create!(main_participant: user).update_columns(state: nil)
    app.conversations.create!(main_participant: other_user)
    dashboard = described_class.new(app: app, range: { from: "2026-11-01", to: "2026-11-30" })
    dashboard.app_user = user
    color = /\Ahsl\(\d+, 70%, 50%\)\z/

    expect(dashboard.conversations).to contain_exactly(
      a_hash_including(id: "opened", label: "opened", value: 3, color: color),
      a_hash_including(id: "closed", label: "closed", value: 2, color: color),
      a_hash_including(id: "unknown", label: "unknown", value: 1, color: color)
    )
  end
end
