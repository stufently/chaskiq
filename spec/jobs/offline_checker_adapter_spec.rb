# frozen_string_literal: true

require "rails_helper"

RSpec.describe OfflineCheckerJob do
  describe "#subscribed? with non-redis adapter" do
    it "returns false when cable adapter is async" do
      original_cable = ActionCable.server.config.cable
      begin
        ActionCable.server.config.cable = { "adapter" => "async" }
        result = described_class.new.send(:subscribed?, "test-key")
        expect(result).to be false
      ensure
        ActionCable.server.config.cable = original_cable
      end
    end
  end
end
