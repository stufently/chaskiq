# frozen_string_literal: true

require "rails_helper"

RSpec.describe BotTask do
  it "finds a task with the requested type among multiple segment predicates" do
    app = FactoryBot.create(:app)
    task = app.bot_tasks.create!(name: "Support bot")
    segments = [
      { value: ["AppUser"], type: "string", attribute: "type", comparison: "in" },
      { value: "user@example.com", type: "string", attribute: "email", comparison: "eq" }
    ]
    task.update_column(:segments, segments)

    expect(app.bot_tasks.where(described_class.infix(["AppUser"]))).to include(task)
  end

  it "builds a type membership predicate for leads" do
    predicate = { value: ["Lead"], type: "string", attribute: "type", comparison: "in" }

    expect(described_class.type_predicate_for(["Lead"])).to eq([predicate])
  end
end
