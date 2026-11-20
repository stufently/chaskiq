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

  describe "#add_error_event URL handling" do
    it "replaces URLs with [url] and truncates to 200 chars" do
      long_text = "Error at https://#{'x' * 200}.example.com/path happened"
      package.send(:add_error_event, conversation, "bypass-internal-0",
                   status: "failed", code: "ERR", text: long_text)

      event = ConversationPartEvent.last
      expect(event).to be_present
      expect(event.action).to include("[url]")
      expect(event.action.length).to be <= 220
      expect(event.data["message"].length).to be <= 200
    end
  end

  describe "#add_error_event dedup with nil status" do
    it "second identical nil-status call adds no new source" do
      package.send(:add_error_event, conversation, "bypass-internal-d2",
                   status: nil, code: "E1", text: "same error text")

      count_before = ConversationPartChannelSource.where(
        provider: "error_test",
        message_source_id: "bypass-internal-d2"
      ).count

      package.send(:add_error_event, conversation, "bypass-internal-d2",
                   status: nil, code: "E1", text: "same error text")

      count_after = ConversationPartChannelSource.where(
        provider: "error_test",
        message_source_id: "bypass-internal-d2"
      ).count

      expect(count_after).to eq(count_before)
    end
  end
end
