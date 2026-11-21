# frozen_string_literal: true

require "rails_helper"

RSpec.describe MessengerEventsChannel, type: :channel do
  describe "#data_submit" do
    it "delegates to ActionTrigger.data_submit with same arguments" do
      data = { "field" => "value" }
      message = double("message")

      expect(ActionTrigger).to receive(:data_submit).with(data, message).and_return(:delegated_result)

      channel = MessengerEventsChannel.allocate
      result = channel.data_submit(data, message)

      expect(result).to eq(:delegated_result)
    end
  end
end
