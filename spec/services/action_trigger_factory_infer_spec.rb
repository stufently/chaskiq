# frozen_string_literal: true

require "rails_helper"

RSpec.describe ActionTriggerFactory do
  let(:app) { FactoryBot.create(:app) }
  let!(:bot) { app.add_agent({ email: "bot@test.com", name: "Bot" }, bot: true).agent }

  around do |example|
    I18n.with_locale(I18n.locale) { example.run }
  end

  def yes_step_uids(user)
    user.lang = "en"
    result = ActionTriggerFactory.infer_for(app: app, user: user)
    yes_path = result.paths.find { |p| p[:title] == "yes" }
    yes_path[:steps].pluck(:step_uid)
  end

  it "returns steps [7, 4] for a user with email" do
    expect(yes_step_uids(bot)).to eq([7, 4])
  end

  it "returns steps [7, 2, 3, 4] for anonymous user with email_requirement Always" do
    app.update!(email_requirement: "Always")
    anon = app.add_anonymous_user({})
    expect(yes_step_uids(anon)).to eq([7, 2, 3, 4])
  end

  it "returns steps [7, 4] for anonymous user with email_requirement never" do
    app.update!(email_requirement: "never")
    anon = app.add_anonymous_user({})
    expect(yes_step_uids(anon)).to eq([7, 4])
  end
end
