# frozen_string_literal: true

require "rails_helper"

RSpec.describe ConversationPart do
  describe "#is_event_message?" do
    it "returns true when messageable is ConversationPartEvent" do
      expect(described_class.new(messageable: ConversationPartEvent.new).is_event_message?).to eq(true)
    end

    it "returns false when messageable is ConversationPartContent" do
      expect(described_class.new(messageable: ConversationPartContent.new).is_event_message?).to eq(false)
    end

    it "returns false without messageable" do
      expect(described_class.new.is_event_message?).to eq(false)
    end
  end

  describe "#is_from_auto_message_campaign?" do
    it "returns true when message_source is UserAutoMessage" do
      expect(described_class.new(message_source: UserAutoMessage.new).is_from_auto_message_campaign?).to eq(true)
    end

    it "returns false when message_source is Campaign" do
      expect(described_class.new(message_source: Campaign.new).is_from_auto_message_campaign?).to eq(false)
    end

    it "returns false without message_source" do
      expect(described_class.new.is_from_auto_message_campaign?).to eq(false)
    end
  end

  describe "renamed" do
    describe "#event_message?" do
      it "returns true when messageable is ConversationPartEvent" do
        expect(described_class.new(messageable: ConversationPartEvent.new).event_message?).to eq(true)
      end

      it "returns false when messageable is ConversationPartContent" do
        expect(described_class.new(messageable: ConversationPartContent.new).event_message?).to eq(false)
      end

      it "returns false without messageable" do
        expect(described_class.new.event_message?).to eq(false)
      end
    end

    describe "#from_auto_message_campaign?" do
      it "returns true when message_source is UserAutoMessage" do
        expect(described_class.new(message_source: UserAutoMessage.new).from_auto_message_campaign?).to eq(true)
      end

      it "returns false when message_source is Campaign" do
        expect(described_class.new(message_source: Campaign.new).from_auto_message_campaign?).to eq(false)
      end

      it "returns false without message_source" do
        expect(described_class.new.from_auto_message_campaign?).to eq(false)
      end
    end
  end
end
