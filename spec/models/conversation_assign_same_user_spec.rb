# frozen_string_literal: true

require "rails_helper"

RSpec.describe Conversation, "assign_user same user" do
  let(:app) { FactoryBot.create(:app) }
  let(:agent1) { app.add_agent({ email: "a1@example.com" }).agent }
  let(:agent2) { app.add_agent({ email: "a2@example.com" }).agent }
  let(:user) { app.add_user(email: "u@example.com") }
  let(:conversation) do
    app.start_conversation(
      message: { html_content: "hi" },
      from: user
    )
  end

  before { conversation.assign_user(agent1) }

  it "returns nil and does not add a message when assigning the same user" do
    expect(conversation.assignee).to eq(agent1)
    initial_count = conversation.messages.count

    result = conversation.assign_user(agent1)
    expect(result).to be_nil
    expect(conversation.messages.count).to eq(initial_count)
  end

  it "adds a message and changes assignee when assigning a different user" do
    initial_count = conversation.messages.count

    conversation.assign_user(agent2)

    expect(conversation.assignee).to eq(agent2)
    expect(conversation.messages.count).to eq(initial_count + 1)
  end
end
