# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Conversation and app mutations" do
  let(:app) { FactoryBot.create(:app) }
  let(:user) { app.add_user(email: "user@example.com") }
  let(:user_context) { { current_user: nil, get_app_user: -> { user } } }
  let(:serialized) do
    { type: "doc", content: [{ type: "paragraph", content: [{ type: "text", text: "rich" }] }] }.to_json
  end
  let(:message) { { text: "plain", html: "<p>rich</p>", serialized: serialized } }

  describe Mutations::Conversations::InsertComment do
    it "persists the supplied text, stripped HTML, and serialized content" do
      conversation = app.conversations.create!(main_participant: user)
      mutation = described_class.new(object: nil, field: nil, context: user_context)

      result = mutation.resolve(app_key: app.key, id: conversation.key, message: message)

      expect(result.fetch(:message).reload.message).to have_attributes(
        text_content: "plain", html_content: "rich", serialized_content: serialized
      )
    end
  end

  describe Mutations::Conversations::StartConversation do
    it "persists the supplied conversation subject" do
      mutation = described_class.new(object: nil, field: nil, context: user_context)

      result = mutation.resolve(
        app_key: app.key,
        id: nil,
        message: message,
        subject: "Hi",
        initiator_channel: nil,
        initiator_block: nil
      )

      expect(result.fetch(:conversation).reload.subject).to eq("Hi")
    end
  end

  describe Mutations::Apps::CreateApp do
    let(:agent) { app.add_agent({ email: "agent@example.com" }).agent }
    let(:mutation) do
      described_class.new(
        object: nil,
        field: nil,
        context: { current_user: agent, request: ActionDispatch::TestRequest.create }
      )
    end

    [nil, "new"].each do |operation|
      it "returns an unsaved app for operation #{operation.inspect}" do
        params = ActionController::Parameters.new(name: "New App", domain_url: "https://new.example.com")
        result = nil

        expect do
          result = mutation.resolve(app_params: params, operation: operation)
        end.not_to(change { agent.apps.count })

        expect(result.fetch(:app)).to be_new_record
      end
    end
  end
end
