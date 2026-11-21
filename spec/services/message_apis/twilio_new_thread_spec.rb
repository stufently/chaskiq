# frozen_string_literal: true

require "rails_helper"

RSpec.describe MessageApis::Twilio::Api, type: :service do
  let(:api) { described_class.allocate }

  describe "#new_conversation_thread?" do
    context "when from is nil" do
      before do
        settings = double(settings: { new_conversations_after: "2" })
        api.instance_variable_set(:@package, settings)
      end

      it "returns false" do
        expect(api.new_conversation_thread?(nil)).to eq(false)
      end
    end

    context "when new_conversations_after setting is blank" do
      before do
        settings = double(settings: {})
        api.instance_variable_set(:@package, settings)
      end

      it "returns false" do
        expect(api.new_conversation_thread?(3.hours.ago)).to eq(false)
      end
    end

    context "when new_conversations_after is set" do
      before do
        settings = double(settings: { new_conversations_after: "2" })
        api.instance_variable_set(:@package, settings)
      end

      it "returns true when from is older than threshold" do
        expect(api.new_conversation_thread?(3.hours.ago)).to eq(true)
      end

      it "returns false when from is newer than threshold" do
        expect(api.new_conversation_thread?(1.hour.ago)).to eq(false)
      end
    end
  end
end
