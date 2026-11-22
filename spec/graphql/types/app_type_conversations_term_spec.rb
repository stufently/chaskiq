# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::AppType, type: :graphql do
  let(:app) { FactoryBot.create(:app) }
  let(:agent) { app.add_agent({ email: "agent-r10c@example.com" }).agent }
  let(:user) { app.add_user({ email: "user-r10c@example.com" }) }
  let!(:conversation) do
    app.start_conversation(
      message: { html_content: "kiwi marmalade" },
      from: user
    )
  end

  let(:type) { described_class.send(:new, app, { current_user: agent }) }

  before do
    allow(type).to receive(:authorize!).and_return(true)
  end

  describe "#conversations with term" do
    it "raises today because Conversation has no ransackable_attributes" do
      expect do
        type.conversations(per: 20, page: 1, filter: nil, sort: nil, term: "marmal")
      end.to raise_error(RuntimeError, /\ARansack needs Conversation attributes explicitly allowlisted/)
    end

    it "passes the expected ransack predicate symbol" do
      conditions = []
      allow(Conversation).to receive(:ransack) do |*args, **opts|
        conditions << (args.first || opts)
        double(result: Conversation.none)
      end

      key = "main_participant_full_name_or_main_participant_name_or_" \
            "main_participant_email_or_main_participant_postal_or_" \
            "main_participant_phone_or_messages_messageable_of_ConversationPartContent_type_text_content_" \
            "i_cont_any"

      result = type.conversations(per: 20, page: 1, filter: nil, sort: nil, term: "marmal")

      expect(result.to_a).to eq([])
      expect(conditions).to eq([{ key.to_sym => "marmal" }])
    end
  end
end
