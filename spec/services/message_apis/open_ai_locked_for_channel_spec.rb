# frozen_string_literal: true

require "rails_helper"

RSpec.describe MessageApis::OpenAi::Api, type: :service do
  let(:app) { FactoryBot.create(:app) }
  let(:user) { app.add_user(email: "user@test.cl", first_name: "User") }
  let(:api) { described_class.allocate }

  let(:conversation) do
    app.start_conversation(message: { text_content: "hi" }, from: user)
  end

  describe "#locked_for_channel?" do
    context "when author is a user" do
      it "returns false" do
        part = double(authorable: user)
        expect(api.locked_for_channel?(conversation, part)).to eq(false)
      end
    end

    context "when author is a bot agent" do
      it "returns false" do
        bot_agent = app.add_agent({ email: "bot@test.cl" }, bot: true).agent
        part = double(authorable: bot_agent)
        expect(api.locked_for_channel?(conversation, part)).to eq(false)
      end
    end

    context "when author is a human agent with open_ai channel" do
      it "returns true and destroys the channel" do
        agent = app.add_agent({ email: "human@test.cl" }).agent
        conversation.conversation_channels.create!(
          provider: "open_ai",
          provider_channel_id: conversation.id
        )
        expect(conversation.conversation_channels.where(provider: "open_ai").count).to eq(1)

        part = double(authorable: agent)
        expect(api.locked_for_channel?(conversation, part)).to eq(true)

        expect(conversation.conversation_channels.where(provider: "open_ai").count).to eq(0)
      end
    end
  end
end
