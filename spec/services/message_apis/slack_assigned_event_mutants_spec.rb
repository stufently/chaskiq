# frozen_string_literal: true

require "rails_helper"

RSpec.describe MessageApis::Slack::Api do
  let(:app) { FactoryBot.create(:app) }
  let(:user) { app.add_user(email: "user@test.cl") }
  let(:api) { described_class.new(config: { "access_token" => "x", "channel_id" => "C1" }) }
  let(:conversation) { app.start_conversation(message: { text_content: "hi" }, from: user) }
  let(:posted_texts) { [] }

  before do
    conversation.conversation_channels.create!(provider: "slack", provider_channel_id: "171.1")
    allow(api).to receive(:post_message) do |_message, blocks, _options|
      posted_texts << blocks.first["text"]["text"]
      instance_double(Faraday::Response, body: { ok: true }.to_json)
    end
  end

  def notify_assignment(action, data)
    part = conversation.messages.create!(authorable: user, event: { action: action, data: data })
    api.notify_message(conversation: conversation, part: part, channel: nil)
  end

  describe "assigned event mutant-killing" do
    it "X05: does not look up a Slack user for a non-assigned event" do
      allow(api).to receive(:get_slack_user_by_email)

      notify_assignment("closed", { "email" => "agent@test.cl" })

      expect(api).not_to have_received(:get_slack_user_by_email)
      expect(posted_texts.fetch(0)).not_to include("<@")
    end

    it "X08: does not add a mention when the Slack user is not found" do
      allow(api).to receive(:get_slack_user_by_email).with("agent@test.cl").and_return(nil)

      notify_assignment("assigned", { "email" => "agent@test.cl" })

      expect(posted_texts.fetch(0)).not_to include("<@")
    end

    it "X09: appends the mention after the event data instead of replacing it" do
      allow(api).to receive(:get_slack_user_by_email).with("agent@test.cl").and_return({ "id" => "U1" })

      notify_assignment("assigned", { "email" => "agent@test.cl" })

      expect(posted_texts.fetch(0)).to eq("*event*: assigned \n *EMAIL*: agent@test.cl\n <@U1>")
    end

    it "X10: separates the mention with a line break" do
      allow(api).to receive(:get_slack_user_by_email).with("agent@test.cl").and_return({ "id" => "U1" })

      notify_assignment("assigned", { "email" => "agent@test.cl" })

      expect(posted_texts.fetch(0)).to include("\n <@U1>")
    end

    it "X11: does not look up a user when the email is blank" do
      allow(api).to receive(:get_slack_user_by_email)

      notify_assignment("assigned", { "email" => "", "name" => "Agent" })

      expect(api).not_to have_received(:get_slack_user_by_email)
    end
  end
end
