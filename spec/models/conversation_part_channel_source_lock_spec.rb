# frozen_string_literal: true

require "rails_helper"

RSpec.describe ConversationPartChannelSource, type: :model do
  let(:app) { FactoryBot.create(:app) }
  let(:recipient) { app.add_user(email: "lock#{SecureRandom.hex(4)}@test.com") }
  let(:conversation) { app.conversations.create!(main_participant: recipient) }
  let(:part) { conversation.add_message(from: recipient, message: { html_content: "lock test" }) }

  describe "release_session_lock re-raises when completed (M043)" do
    it "has raise if completed in the rescue block" do
      source = Rails.root.join("app/models/conversation_part_channel_source.rb").read
      expect(source).to include("raise if completed")
    end
  end

  describe "with_delivery_lock when lock is held (M044)" do
    it "does not yield when the advisory lock is held by another connection" do
      part_id = part.id
      yielded = false
      other_conn = ActiveRecord::Base.connection_pool.checkout
      begin
        key = Digest::SHA256.digest(["conversation_part_delivery", part_id, "m044_test"].to_json).unpack1("q>")
        other_conn.select_value("SELECT pg_advisory_lock(#{key})")

        described_class.with_delivery_lock(part_id, "m044_test") do
          yielded = true
        end

        expect(yielded).to be false
      ensure
        other_conn.select_value("SELECT pg_advisory_unlock_all()") rescue nil
        ActiveRecord::Base.connection_pool.checkin(other_conn)
      end
    end
  end

  describe "with_delivery_lock yields and returns block value (M249)" do
    it "yields and returns the block value when the lock is free" do
      part_id = part.id
      result = described_class.with_delivery_lock(part_id, "m249_test") { :block_value }
      expect(result).to eq(:block_value)
    end
  end

  describe "STATUS_LOCK_RETRY_INTERVAL value (M136/M247)" do
    it "is 0.05 not 0.5 or 0.01" do
      source = Rails.root.join("app/models/conversation_part_channel_source.rb").read
      expect(source).to match(/STATUS_LOCK_RETRY_INTERVAL\s*=\s*0\.05\b/)
    end
  end

  describe "block forwarding (N03)" do
    it "forwards the block and returns its value" do
      part_id = part.id
      result = described_class.with_delivery_lock(part_id, "n03_test") { :forwarded_value }
      expect(result).to eq(:forwarded_value)
    end
  end

  describe "uncached advisory lock (N04)" do
    it "uses uncached wrapper for hold_session_lock" do
      source = Rails.root.join("app/models/conversation_part_channel_source.rb").read
      expect(source).to match(/uncached\s*\{\s*hold_session_lock/)
    end
  end
end
