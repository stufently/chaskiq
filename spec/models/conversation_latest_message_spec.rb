# frozen_string_literal: true

require "rails_helper"

RSpec.describe Conversation, type: :model do
  let(:app) { FactoryBot.create(:app) }
  let(:agent) { app.add_agent({ email: "agent@test.cl" }).agent }
  let(:user) { app.add_user(email: "user@test.cl", first_name: "User") }

  let(:conversation) do
    app.start_conversation(
      message: { html_content: "first" },
      from: user
    )
  end

  describe "#latest_message" do
    it "returns the last message part by id desc" do
      conversation
      conversation.add_message(from: user, message: { html_content: "second" })
      conversation.add_message(from: user, message: { html_content: "third" })

      expect(conversation.reload.latest_message.messageable.html_content).to eq("third")
    end
  end

  describe "#public_latest_message" do
    it "returns the last non-private message part" do
      conversation
      conversation.add_message(from: user, message: { html_content: "public msg" })
      conversation.add_private_note(from: agent, message: { html_content: "private note" })

      expect(conversation.reload.public_latest_message.messageable.html_content).to eq("public msg")
    end
  end
end
