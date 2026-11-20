# frozen_string_literal: true

require "rails_helper"

RSpec.describe ActionTriggerFactory do
  let(:app) { FactoryBot.create(:app) }
  let(:user) { app.add_user(email: "user@example.com", first_name: "Test") }
  let(:bot) { app.bot_tasks.create(title: "bot", bot_type: "new_conversations") }

  describe ".find_by_segment" do
    let(:rules) do
      [
        {
          "trigger" => bot.id,
          "predicates" => [
            { "attribute" => "email", "comparison" => "eq", "type" => "string", "value" => user.email }
          ]
        }
      ]
    end

    it "returns the bot task when the user matches the segment" do
      result = described_class.find_by_segment(app: app, user: user, rules: rules)
      expect(result).to eq(bot)
    end

    it "returns nil when the user does not match the segment" do
      other_user = app.add_user(email: "other@example.com", first_name: "Other")
      result = described_class.find_by_segment(app: app, user: other_user, rules: rules)
      expect(result).to be_nil
    end
  end
end
