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
end
