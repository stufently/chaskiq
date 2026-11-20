# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Conversation author mutations" do
  let(:app) { FactoryBot.create(:app) }
  let(:agent) { app.add_agent({ email: "agent@test.cl", first_name: "Agent" }).agent }
  let(:app_user) { app.add_user(email: "user@test.cl", first_name: "User") }

  before do
    app.update!(owner_id: agent.id)
  end

  describe Mutations::Conversations::InsertComment do
    it "sets the author to the app_user from context" do
      conversation = app.conversations.create(main_participant: app_user)
      mutation = described_class.new(
        object: nil,
        field: nil,
        context: {
          current_user: nil,
          get_app_user: -> { app_user }
        }
      )

      serialized = { type: "doc", content: [{ type: "paragraph", content: [{ type: "text", text: "test" }] }] }.to_json
      result = mutation.resolve(
        app_key: app.key,
        id: conversation.key,
        message: { html: "<p>test</p>", serialized: serialized, text: "test" }
      )

      expect(result[:message].authorable).to eq(app_user)
    end
  end

  describe Mutations::Conversations::StartConversation do
    it "sets the main_participant from the app_user context" do
      mutation = described_class.new(
        object: nil,
        field: nil,
        context: {
          current_user: nil,
          get_app_user: -> { app_user }
        }
      )

      serialized = { type: "doc", content: [{ type: "paragraph", content: [{ type: "text", text: "hello" }] }] }.to_json
      result = mutation.resolve(
        app_key: app.key,
        id: nil,
        message: { html: "<p>hello</p>", serialized: serialized, text: "hello" },
        subject: nil,
        initiator_channel: nil,
        initiator_block: nil
      )

      expect(result[:conversation].main_participant).to eq(app_user)
    end
  end

  describe Mutations::Apps::CreateApp do
    it "creates an app owned by the agent" do
      mutation = described_class.new(
        object: nil,
        field: nil,
        context: {
          current_user: agent,
          request: ActionDispatch::TestRequest.create
        }
      )

      result = mutation.resolve(
        app_params: ActionController::Parameters.new(name: "New App", domain_url: "http://new.example.com"),
        operation: "create"
      )

      expect(result[:app]).to be_persisted
      expect(result[:app].owner).to eq(agent)
      expect(agent.apps.reload).to include(result[:app])
    end
  end
end
