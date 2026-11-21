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

  def notify_assignment(data)
    part = conversation.messages.create!(authorable: user, event: { action: "assigned", data: data })
    api.notify_message(conversation: conversation, part: part, channel: nil)
  end

  it "posts the assignment when event data is nil" do
    notify_assignment(nil)

    expect(posted_texts).to eq(["*event*: assigned \n "])
  end

  it "posts the assignment when event data is an array" do
    notify_assignment(%w[a b])

    expect(posted_texts).to eq(["*event*: assigned \n "])
  end

  it "posts the assignment without looking up a user when the email is absent" do
    allow(api).to receive(:get_slack_user_by_email)

    notify_assignment({ "name" => "Agent" })

    expect(api).not_to have_received(:get_slack_user_by_email)
    expect(posted_texts).to eq(["*event*: assigned \n *NAME*: Agent"])
  end

  it "mentions the Slack user found by the assignee email" do
    allow(api).to receive(:get_slack_user_by_email).with("agent@test.cl").and_return({ "id" => "U1" })

    notify_assignment({ "email" => "agent@test.cl" })

    expect(posted_texts.fetch(0)).to include("<@U1>")
  end
end
