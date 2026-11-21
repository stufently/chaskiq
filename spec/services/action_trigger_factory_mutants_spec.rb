# frozen_string_literal: true

require "rails_helper"

RSpec.describe ActionTriggerFactory do
  describe ".find_by_segment" do
    let(:app) { FactoryBot.create(:app) }
    let(:user) { app.add_user(email: "user@example.com") }
    let(:bot) { app.bot_tasks.create!(name: "Support bot") }

    def email_rule(task, email)
      {
        "trigger" => task.id,
        "predicates" => [{ "attribute" => "email", "comparison" => "eq", "type" => "string", "value" => email }]
      }
    end

    it "matches a rule with no predicates" do
      rules = [{ "trigger" => bot.id }]

      expect(described_class.find_by_segment(app: app, user: user, rules: rules)).to eq(bot)
    end

    it "continues to the next rule when the first rule does not match" do
      other_bot = app.bot_tasks.create!(name: "Other bot")
      rules = [email_rule(other_bot, "other@example.com"), email_rule(bot, user.email)]

      expect(described_class.find_by_segment(app: app, user: user, rules: rules)).to eq(bot)
    end

    it "rejects a matching rule whose bot belongs to another app" do
      other_app = FactoryBot.create(:app)
      other_bot = other_app.bot_tasks.create!(name: "Other app bot")
      rules = [email_rule(other_bot, user.email)]

      expect do
        described_class.find_by_segment(app: app, user: user, rules: rules)
      end.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
