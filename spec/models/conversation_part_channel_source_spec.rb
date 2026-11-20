# frozen_string_literal: true

require "rails_helper"

RSpec.describe ConversationPartChannelSource, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"

  let(:app) { FactoryBot.create(:app) }
  let(:recipient) { app.add_user(email: "recipient@example.com") }
  let(:conversation) { app.conversations.create!(main_participant: recipient) }
  let(:part) { conversation.add_message(from: recipient, message: { html_content: "Test message" }) }
  let(:sources) { part.conversation_part_channel_sources }

  it "enforces one outgoing slot per part and provider and allows legacy rows" do
    sources.create!(provider: "twilio", delivery_index: 0)
    sources.create!(provider: "vonage", delivery_index: 0)
    2.times { sources.create!(provider: "twilio", message_source_id: "legacy") }

    expect { sources.create!(provider: "twilio", delivery_index: 0) }.to raise_error(ActiveRecord::RecordNotUnique)
    expect(sources.count).to eq(4)
  end

  it "releases the session lock after an exception so another session can send" do
    expect do
      described_class.with_delivery_lock(part.id, "twilio") { raise "delivery broke" }
    end.to raise_error("delivery broke")

    part_id = part.id
    other_session = Thread.new do
      described_class.with_delivery_lock(part_id, "twilio") { :acquired }
    end
    expect(other_session.value).to eq(:acquired)
  end

  it "discards the aborted session when unlocking fails and preserves the original exception" do
    part_id = part.id
    adapter = nil
    expect do
      described_class.with_delivery_lock(part_id, "twilio") do
        described_class.with_connection do |connection|
          adapter = connection
          connection.begin_db_transaction
          connection.execute("SELECT 1 / 0")
        end
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /division by zero/)

    expect(adapter).not_to be_active
    other_session = Thread.new { described_class.with_delivery_lock(part_id, "twilio") { :acquired } }
    expect(other_session.value).to eq(:acquired)
  ensure
    adapter.throw_away! if adapter&.active?
  end

  it "warns and returns the block result if the session already lost its lock" do
    allow(Rails.logger).to receive(:warn)
    part_id = part.id
    result = described_class.with_connection do |connection|
      previous_level = connection.client_min_messages
      connection.client_min_messages = "error"
      described_class.with_delivery_lock(part_id, "twilio") do
        connection.execute("SELECT pg_advisory_unlock_all()")
        :delivered
      end
    ensure
      connection.client_min_messages = previous_level if previous_level
    end

    expect(result).to eq(:delivered)
    expect(Rails.logger).to have_received(:warn).with(/advisory lock was lost/)
  end

  it "times out a contended status event lock and lets a retry succeed" do
    conversation_id = conversation.id
    event = { provider: "dialog_360", message_source_id: "wamid.1", action: "errored: delivery failed" }
    locked = Queue.new
    release = Queue.new
    owner = Thread.new do
      described_class.with_status_event_lock(conversation_id, event) do
        locked << true
        release.pop
      end
    end

    Timeout.timeout(8) do
      locked.pop
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      expect do
        described_class.with_status_event_lock(conversation_id, event) { raise "another session holds this lock" }
      end.to raise_error(/timed out acquiring status event advisory lock/i)
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be >= 5
    end

    release << true
    owner.value
    expect(described_class.with_status_event_lock(conversation_id, event) { :acquired }).to eq(:acquired)
  ensure
    release << true if owner&.alive?
    owner&.join(5)
  end
end
