# frozen_string_literal: true

require "rails_helper"

RSpec.describe ConversationPartChannelSource, type: :model do
  let(:app) { FactoryBot.create(:app) }
  let(:recipient) { app.add_user(email: "lock#{SecureRandom.hex(4)}@test.com") }
  let(:conversation) { app.conversations.create!(main_participant: recipient) }
  let(:part) { conversation.add_message(from: recipient, message: { html_content: "lock test" }) }

  describe "with_delivery_lock error propagation after unlock failure (M043)" do
    it "re-raises PG::ConnectionBad when unlock fails after block completed" do
      part_id = part.id
      conn_ref = nil
      expect {
        described_class.with_delivery_lock(part_id, "m043_test") do
          described_class.with_connection do |conn|
            conn_ref = conn
            conn.execute("SELECT pg_advisory_unlock_all()")
          end
          :block_completed
        end
      }.to raise_error(PG::ConnectionBad)
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

  describe "with_status_event_lock retry interval (M136/M247)" do
    it "sleeps with 0.05 second intervals" do
      conversation_id = conversation.id
      event = { provider: "m136_prov", message_source_id: "src-m136", action: "errored: m136" }
      slept_with = []

      other_conn = ActiveRecord::Base.connection_pool.checkout
      begin
        identity = ["conversation_status_event", conversation_id, "m136_prov", "src-m136", "errored: m136"]
        key = Digest::SHA256.digest(identity.to_json).unpack1("q>")
        other_conn.select_value("SELECT pg_advisory_lock(#{key})")

        Thread.new do
          sleep 0.2
          other_conn.select_value("SELECT pg_advisory_unlock(#{key})") rescue nil
        end

        original_sleep = method(:sleep)
        define_method(:sleep) { |val| slept_with << val; original_sleep.call(val) }

        described_class.with_status_event_lock(conversation_id, event) { :done }

        expect(slept_with).to include(0.05)
        expect(slept_with).not_to include(0.5)
        expect(slept_with).not_to include(0.01)
      ensure
        other_conn.select_value("SELECT pg_advisory_unlock_all()") rescue nil
        ActiveRecord::Base.connection_pool.checkin(other_conn)
      end
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
    it "does not use query cache for advisory lock check" do
      part_id = part.id
      other_conn = ActiveRecord::Base.connection_pool.checkout
      begin
        key = Digest::SHA256.digest(["conversation_part_delivery", part_id, "n04_test"].to_json).unpack1("q>")
        other_conn.select_value("SELECT pg_advisory_lock(#{key})")

        yielded = false
        ActiveRecord::Base.cache do
          described_class.with_delivery_lock(part_id, "n04_test") { yielded = true }
        end
        expect(yielded).to be false
      ensure
        other_conn.select_value("SELECT pg_advisory_unlock_all()") rescue nil
        ActiveRecord::Base.connection_pool.checkin(other_conn)
      end
    end
  end
end
