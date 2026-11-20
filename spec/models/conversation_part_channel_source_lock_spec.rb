# frozen_string_literal: true

require "rails_helper"

RSpec.describe ConversationPartChannelSource, type: :model do
  let(:app) { FactoryBot.create(:app) }
  let(:recipient) { app.add_user(email: "lock#{SecureRandom.hex(4)}@test.com") }
  let(:conversation) { app.conversations.create!(main_participant: recipient) }
  let(:part) { conversation.add_message(from: recipient, message: { html_content: "lock test" }) }

  describe "with_delivery_lock error propagation (M043)" do
    it "re-raises the original error when unlock fails after block completed" do
      part_id = part.id
      call_count = 0
      original = ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.instance_method(:select_value)

      allow(ActiveRecord::ConnectionAdapters::PostgreSQLAdapter).to receive(:select_value) do |conn, sql, *args, **kwargs|
        call_count += 1
        if sql.to_s.include?("pg_advisory_unlock")
          raise PG::ConnectionBad, "simulated connection loss"
        end
        original.bind_call(conn, sql, *args, **kwargs)
      end

      expect {
        described_class.with_delivery_lock(part_id, "m043_test") { :ok }
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

  describe "STATUS_LOCK_RETRY_INTERVAL (M136/M247)" do
    it "retries with 0.05 second sleep intervals" do
      conversation_id = conversation.id
      event = { provider: "m136p", message_source_id: "src-m136", action: "errored: m136" }

      other_conn = ActiveRecord::Base.connection_pool.checkout
      begin
        identity = ["conversation_status_event", conversation_id, "m136p", "src-m136", "errored: m136"]
        key = Digest::SHA256.digest(identity.to_json).unpack1("q>")
        other_conn.select_value("SELECT pg_advisory_lock(#{key})")

        Thread.new do
          sleep 0.25
          other_conn.select_value("SELECT pg_advisory_unlock(#{key})") rescue nil
        end

        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        described_class.with_status_event_lock(conversation_id, event) { :done }
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start

        expect(elapsed).to be >= 0.2
        expect(elapsed).to be < 1.0
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
