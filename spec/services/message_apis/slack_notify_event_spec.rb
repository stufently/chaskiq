# frozen_string_literal: true

require "rails_helper"

RSpec.describe MessageApis::Slack::Api do
  describe "#notify_message" do
    let(:api) { described_class.new(config: { "access_token" => "x", "channel_id" => "C1" }) }
    let(:app) { FactoryBot.create(:app) }
    let(:user) { app.add_user(email: "visitor@example.com") }
    let(:conversation) { app.start_conversation(message: { text_content: "Hello" }, from: user) }
    let(:action) { "closed" }
    let(:data) { nil }
    let(:part) { conversation.messages.create!(authorable: user, event: { action: action, data: data }) }
    let(:reply) { { ok: true, ts: "9.9" } }

    before do
      allow(api).to receive(:post_message).and_return(instance_double(Faraday::Response, body: reply.to_json))
      allow(api).to receive(:get_slack_user_by_email)
    end

    def notify_part
      api.notify_message(conversation: conversation, part: part, channel: nil)
    end

    def event_blocks(text)
      [{ "type" => "section", "text" => { "type" => "mrkdwn", "text" => text } }]
    end

    it "does not post an event when the conversation has no Slack thread" do
      notify_part

      expect(api).not_to have_received(:post_message)
    end

    context "with a Slack thread" do
      before do
        conversation.conversation_channels.create!(provider: "slack", provider_channel_id: "171.1")
      end

      it "does not repost a part already delivered to Slack" do
        part.conversation_part_channel_sources.create!(provider: "slack", message_source_id: "8.8")

        notify_part

        expect(api).not_to have_received(:post_message)
      end

      it "posts to the configured channel and thread and stores the Slack message ID" do
        notify_part

        expect(api).to have_received(:post_message)
          .with("new message", anything, hash_including(channel: "C1", thread_ts: "171.1"))
        expect(part.conversation_part_channel_sources.find_by!(provider: "slack").message_source_id).to eq("9.9")
      end

      context "when Slack rejects the post" do
        let(:reply) { { ok: false } }

        it "does not record a Slack delivery" do
          notify_part

          expect(api).to have_received(:post_message)
          expect(part.conversation_part_channel_sources.where(provider: "slack")).to be_empty
        end
      end

      context "when the event data has a blank field" do
        let(:data) { { "label" => "Done", "status" => "" } }

        it "posts only the nonblank event field" do
          notify_part

          expect(api).to have_received(:post_message)
            .with("new message", event_blocks("*event*: closed \n *LABEL*: Done"), anything)
        end
      end

      context "when the event data is an array" do
        let(:data) { [%w[label Done]] }

        it "posts the event without interpreting the array as named fields" do
          notify_part

          expect(api).to have_received(:post_message)
            .with("new message", event_blocks("*event*: closed \n "), anything)
        end
      end

      context "when an assignment has no email address" do
        let(:action) { "assigned" }
        let(:data) { {} }

        it "posts without looking up a Slack user or adding a mention" do
          notify_part

          expect(api).not_to have_received(:get_slack_user_by_email)
          expect(api).to have_received(:post_message)
            .with("new message", event_blocks("*event*: assigned \n "), anything)
        end
      end

      context "when the assignee's email resolves to a Slack user" do
        let(:action) { "assigned" }
        let(:data) { { "email" => "agent@example.com" } }

        it "mentions the Slack user's ID in the posted event" do
          allow(api).to receive(:get_slack_user_by_email).and_return({ "id" => "U1", "name" => "bob" })

          notify_part

          expect(api).to have_received(:get_slack_user_by_email).with("agent@example.com")
          expect(api).to have_received(:post_message)
            .with("new message", event_blocks("*event*: assigned \n *EMAIL*: agent@example.com\n <@U1>"), anything)
        end
      end
    end
  end
end
