# frozen_string_literal: true

require "rails_helper"

RSpec.describe MessageApis::BasePackage do
  let(:app) { FactoryBot.create(:app) }
  let(:recipient) { app.add_user(email: "errors#{SecureRandom.hex(4)}@test.com") }
  let(:conversation) { app.conversations.create!(main_participant: recipient) }

  let(:plugin_class) do
    klass = Class.new(described_class)
    klass.const_set(:PROVIDER, "error_test")
    klass.define_method(:get_message_id) { |data| data["id"] }
    klass
  end
  let(:package) { plugin_class.new(config: {}) }

  describe "#add_error_event" do
    it "truncates URLs to [url] and limits to 200 chars" do
      long_url = "https://#{'x' * 290}.com/path"
      package.send(:add_error_event, conversation, "bypass-internal-0",
                   status: nil, code: "ERR", text: long_url)

      event = ConversationPartEvent.where(action: /errored/).last
      expect(event).to be_present
      action_text = event.action.sub("errored: ", "")
      expect(action_text).to include("[url]")
      expect(action_text.length).to be <= 200
    end
  end

  describe "#add_error_event_once dedup" do
    it "only creates one errored part for the same event reported twice" do
      event = {
        action: "errored: test-dedup",
        provider: "error_test",
        message_source_id: "bypass-internal-dedup",
        data: { status: nil, code: "ERR", message: "test-dedup" }
      }

      conversation.add_message_event(**event)
      conversation.add_message_event(**event)

      parts = conversation.messages.joins(:conversation_part_channel_sources)
                          .where(messageable_type: "ConversationPartEvent")
                          .where("conversation_part_channel_sources.message_source_id = ?", "bypass-internal-dedup")
      expect(parts.count).to eq(1)
    end
  end

  describe "#add_error_event with nil status uses dedup" do
    it "second identical call adds no new part" do
      package.send(:add_error_event, conversation, "bypass-internal-d2",
                   status: nil, code: "E1", text: "same error")
      package.send(:add_error_event, conversation, "bypass-internal-d2",
                   status: nil, code: "E1", text: "same error")

      errored_events = ConversationPartEvent.where(action: "errored: same error")
      sources = ConversationPartChannelSource.where(
        provider: "error_test",
        message_source_id: "bypass-internal-d2"
      )
      expect(sources.count).to eq(1)
    end
  end
end
