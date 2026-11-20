# frozen_string_literal: true

require "rails_helper"

RSpec.describe BotTask, type: :model do
  let(:app) { FactoryBot.create(:app) }

  it "is invalid without a name" do
    bot_task = BotTask.new(app: app, name: nil)
    expect(bot_task).not_to be_valid
    expect(bot_task.errors[:name]).to be_present
  end

  it "finds tasks by infix predicate for AppUser type" do
    bot_task = app.bot_tasks.create(name: "Test Bot")
    predicate = BotTask.type_predicate_for(["AppUser"])
    bot_task.update_column(:segments, predicate)

    found = BotTask.where(BotTask.infix(["AppUser"]))
    expect(found).to include(bot_task)
  end

  it "does not find tasks with a different predicate type" do
    bot_task = app.bot_tasks.create(name: "Lead Bot")
    predicate = BotTask.type_predicate_for(["Lead"])
    bot_task.update_column(:segments, predicate)

    found = BotTask.where(BotTask.infix(["AppUser"]))
    expect(found).not_to include(bot_task)
  end

  it "generates SQL with the @> containment operator" do
    sql = BotTask.where(BotTask.infix(["AppUser"])).to_sql
    expect(sql).to include("@>")
  end
end
