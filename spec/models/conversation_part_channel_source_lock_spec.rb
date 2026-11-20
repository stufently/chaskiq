# frozen_string_literal: true

require "rails_helper"

RSpec.describe ConversationPartChannelSource, type: :model do
  let(:app) { FactoryBot.create(:app) }
  let(:recipient) { app.add_user(email: "lock#{SecureRandom.hex(4)}@test.com") }
  let(:conversation) { app.conversations.create!(main_participant: recipient) }
  let(:part) { conversation.add_message(from: recipient, message: { html_content: "lock test" }) }

  describe "with_delivery_lock error propagation after unlock failure" do
    it "re-raises the error when unlock fails after the block completed" do
      part_id = part.id
      expect {
        described_class.with_delivery_lock(part_id, "test_provider") do
          described_class.with_connection do |conn|
            conn.execute("SELECT pg_advisory_unlock_all()")
          end
          raise PG::ConnectionBad, "simulated"
        end
      }.to raise_error(PG::ConnectionBad, "simulated")
    end
  end

  describe "with_delivery_lock when lock is held" do
    it "does not yield when the advisory lock is held by another connection" do
      part_id = part.id
      yielded = false
      other_conn = ActiveRecord::Base.connection_pool.checkout
      begin
        key = Digest::SHA256.digest(["conversation_part_delivery", part_id, "test_provider"].to_json).unpack1("q>")
        other_conn.select_value("SELECT pg_advisory_lock(#{key})")

        described_class.with_delivery_lock(part_id, "test_provider") do
          yielded = true
        end

        expect(yielded).to be false
      ensure
        other_conn.select_value("SELECT pg_advisory_unlock_all()") rescue nil
        ActiveRecord::Base.connection_pool.checkin(other_conn)
      end
    end
  end

  describe "with_delivery_lock yields and returns block value when free" do
    it "yields and returns the block value when the lock is free" do
      part_id = part.id
      result = described_class.with_delivery_lock(part_id, "test_provider2") { :block_value }
      expect(result).to eq(:block_value)
    end
  end

  describe "with_status_event_lock retry interval" do
    it "sleeps with 0.05 second intervals" do
      conversation_id = conversation.id
      event = { provider: "test_prov", message_source_id: "src-1", action: "errored: test" }
      slept_with = []
      allow_any_instance_of(Object).to receive(:sleep) { |_, val| slept_with << val }

      other_conn = ActiveRecord::Base.connection_pool.checkout
      begin
        identity = ["conversation_status_event", conversation_id, "test_prov", "src-1", "errored: test"]
        key = Digest::SHA256.digest(identity.to_json).unpack1("q>")
        other_conn.select_value("SELECT pg_advisory_lock(#{key})")

        Thread.new do
          sleep 0.2
          other_conn.select_value("SELECT pg_advisory_unlock(#{key})") rescue nil
        end

        described_class.with_status_event_lock(conversation_id, event) { :done }
        expect(slept_with).to include(0.05)
      ensure
        other_conn.select_value("SELECT pg_advisory_unlock_all()") rescue nil
        ActiveRecord::Base.connection_pool.checkin(other_conn)
      end
    end
  end

  describe "with_status_event_lock retry interval is 0.05 not 0.01" do
    it "uses 0.05 not 0.01 for sleep" do
      conversation_id = conversation.id
      event = { provider: "test_prov2", message_source_id: "src-2", action: "errored: test2" }
      slept_with = []

      other_conn = ActiveRecord::Base.connection_pool.checkout
      begin
        identity = ["conversation_status_event", conversation_id, "test_prov2", "src-2", "errored: test2"]
        key = Digest::SHA256.digest(identity.to_json).unpack1("q>")
        other_conn.select_value("SELECT pg_advisory_lock(#{key})")

        Thread.new do
          sleep 0.2
          other_conn.select_value("SELECT pg_advisory_unlock(#{key})") rescue nil
        end

        allow(Kernel).to receive(:sleep) do |val|
          slept_with << val
          Kernel.method(:sleep).super_method.call(val) rescue nil
        end

        described_class.with_status_event_lock(conversation_id, event) { :done }
        expect(slept_with).to all(be <= 0.05)
        expect(slept_with).not_to include(0.01)
      ensure
        other_conn.select_value("SELECT pg_advisory_unlock_all()") rescue nil
        ActiveRecord::Base.connection_pool.checkin(other_conn)
      end
    end
  end

  describe "block forwarding to hold_session_lock" do
    it "forwards the block and returns its value" do
      part_id = part.id
      result = described_class.with_delivery_lock(part_id, "fwd_test") { :forwarded }
      expect(result).to eq(:forwarded)
    end
  end

  describe "uncached advisory lock" do
    it "does not use query cache for advisory lock check" do
      part_id = part.id
      ActiveRecord::Base.cache do
        described_class.with_delivery_lock(part_id, "uncached_test") { :first }
      end

      other_conn = ActiveRecord::Base.connection_pool.checkout
      begin
        key = Digest::SHA256.digest(["conversation_part_delivery", part_id, "uncached_test"].to_json).unpack1("q>")
        other_conn.select_value("SELECT pg_advisory_lock(#{key})")

        yielded = false
        ActiveRecord::Base.cache do
          described_class.with_delivery_lock(part_id, "uncached_test") { yielded = true }
        end
        expect(yielded).to be false
      ensure
        other_conn.select_value("SELECT pg_advisory_unlock_all()") rescue nil
        ActiveRecord::Base.connection_pool.checkin(other_conn)
      end
    end
  end
end
