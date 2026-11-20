# frozen_string_literal: true

require "rails_helper"

RSpec.describe OfflineCheckerJob do
  describe "#perform with non-redis adapter" do
    it "marks user offline when cable adapter is not redis" do
      user = AppUser.create!(email: "offtest#{SecureRandom.hex(4)}@test.com", state: "online")

      original_cable = ActionCable.server.config.cable
      begin
        ActionCable.server.config.cable = { "adapter" => "async" }
        described_class.new.perform(user.id, "test-key")
        user.reload
        expect(user.offline?).to be true
      ensure
        ActionCable.server.config.cable = original_cable
      end
    end
  end
end
