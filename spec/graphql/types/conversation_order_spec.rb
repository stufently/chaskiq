# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Conversation types ordering", type: :graphql do
  let(:app) { FactoryBot.create(:app) }
  let(:agent) { app.add_agent({ email: "agent@test.cl" }).agent }
  let(:user) { app.add_user(email: "user@test.cl", first_name: "User") }

  describe "Types::ConversationType#messages" do
    it "returns messages ordered by id desc" do
      conversation = app.start_conversation(message: { html_content: "initial" }, from: user)
      part1 = conversation.add_message(from: user, message: { html_content: "first" })
      part2 = conversation.add_message(from: user, message: { html_content: "second" })
      part3 = conversation.add_message(from: user, message: { html_content: "third" })

      context = { current_user: agent }
      type_instance = Types::ConversationType.send(:new, conversation, context)

      result = type_instance.messages(per: 10, page: 1)
      ids = result.map(&:id)
      # Messages are ordered by id desc, including the initial message
      expect(ids.first(3)).to eq([part3.id, part2.id, part1.id])
    end
  end

  describe "Types::PublicConversationType#messages" do
    it "returns visible messages ordered by id desc, excluding private notes" do
      conversation = app.start_conversation(message: { html_content: "initial" }, from: user)
      part1 = conversation.add_message(from: user, message: { html_content: "first" })
      private_note = conversation.add_private_note(from: agent, message: { html_content: "secret" })
      part2 = conversation.add_message(from: user, message: { html_content: "second" })

      context = { current_user: agent }
      type_instance = Types::PublicConversationType.send(:new, conversation, context)

      result = type_instance.messages(per: 10, page: 1)
      ids = result.map(&:id)
      # Visible messages are ordered by id desc, private note excluded
      expect(ids).not_to include(private_note.id)
      expect(ids.first(2)).to eq([part2.id, part1.id])
    end
  end

  describe "Types::MessengerType#conversations" do
    it "returns conversations ordered by updated_at desc" do
      conv1 = app.start_conversation(message: { html_content: "first" }, from: user)
      conv2 = app.start_conversation(message: { html_content: "second" }, from: user)

      # Update conv1's updated_at to be later
      conv1.update_column(:updated_at, 1.hour.from_now)

      context = { current_user: agent, get_app_user: -> { user } }
      messenger_type = Types::MessengerType.send(:new, app, context)
      allow(messenger_type).to receive(:authorize!).and_return(true)

      result = messenger_type.conversations(page: 1, per: 10)
      ids = result.map(&:id)
      expect(ids).to eq([conv1.id, conv2.id])
    end
  end
end
