# frozen_string_literal: true

require "rails_helper"

RSpec.describe Message, type: :model do
  let(:app) { FactoryBot.create(:app) }

  describe ".ordered" do
    it "returns BotTasks ordered by position ascending" do
      bot1 = BotTask.create!(app: app, name: "first", state: "enabled")
      bot2 = BotTask.create!(app: app, name: "second", state: "enabled")
      bot3 = BotTask.create!(app: app, name: "third", state: "enabled")

      # Set positions in reverse order via update_column to bypass callbacks
      bot3.update_column(:position, 1)
      bot2.update_column(:position, 2)
      bot1.update_column(:position, 3)

      ids = BotTask.where(id: [bot1.id, bot2.id, bot3.id]).ordered.map(&:id)
      expect(ids).to eq([bot3.id, bot2.id, bot1.id])
    end
  end
end
