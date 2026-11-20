# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Conversations::UpdateState do
  let(:app) { FactoryBot.create(:app) }
  let(:agent) { app.add_agent({ email: "agent@test.cl", first_name: "Agent" }).agent }
  let(:user) { app.add_user(email: "user@test.cl", first_name: "User") }

  before do
    app.update!(owner_id: agent.id)
  end

  def build_mutation
    described_class.new(
      object: nil,
      field: nil,
      context: {
        current_user: agent,
        request: ActionDispatch::TestRequest.create
      }
    )
  end

  def create_and_close
    conversation = app.conversations.create(main_participant: user)
    build_mutation.resolve(app_key: app.key, conversation_id: conversation.id, state: "close")
    conversation.reload
    conversation
  end

  it "closes a conversation" do
    conversation = create_and_close
    expect(conversation.state).to eq("closed")
  end

  it "reopens a closed conversation" do
    conversation = create_and_close
    expect(conversation.state).to eq("closed")

    build_mutation.resolve(app_key: app.key, conversation_id: conversation.id, state: "reopen")
    conversation.reload
    expect(conversation.state).to eq("opened")
  end

  it "does not change state for an unknown state value" do
    conversation = create_and_close
    expect(conversation.state).to eq("closed")

    build_mutation.resolve(app_key: app.key, conversation_id: conversation.id, state: "destroy")
    conversation.reload
    expect(conversation.state).to eq("closed")
  end
end
