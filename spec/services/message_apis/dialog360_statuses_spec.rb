# frozen_string_literal: true

require "rails_helper"

RSpec.describe MessageApis::Dialog360::Api do
  let(:app) { App.create!(name: "mutb-d360-#{SecureRandom.hex(4)}", key: SecureRandom.hex(8)) }
  let(:config) do
    { "api_key" => "test", "api_secret" => "secret", "user_id" => "+15551234567",
      "sandbox" => true, :package => OpenStruct.new(app: app) }
  end
  let(:api) { described_class.new(config: config) }

  after { app.destroy }

  describe "process_statuses with read status" do
    it "calls process_read for read statuses" do
      part = instance_double("ConversationPart")
      allow(part).to receive(:read!)
      channel_source = instance_double("ConversationPartChannelSource", conversation_part: part)
      allow(ConversationPartChannelSource).to receive(:find_by)
        .with(provider: "dialog_360", message_source_id: "msg-123")
        .and_return(channel_source)

      api.process_statuses([{ "status" => "read", "id" => "msg-123" }])

      expect(part).to have_received(:read!)
    end
  end

  describe "prepare_initiator_channel_for with blank profile_id" do
    it "rolls back the transaction when profile_id is blank" do
      user = AppUser.create!(email: "d360test#{SecureRandom.hex(4)}@test.com")
      conversation = Conversation.create!(assignee: nil, main_participant: user, app: app)

      allow(api).to receive(:add_participant_to_existing_user).and_return(nil)

      expect {
        api.prepare_initiator_channel_for(conversation, config[:package])
      }.not_to change(ConversationChannel, :count)
    ensure
      conversation&.destroy
      user&.destroy
    end
  end

  describe "add_participant with empty string sender" do
    it "creates a participant for empty string (truthy)" do
      user = AppUser.create!(email: "d360empty#{SecureRandom.hex(4)}@test.com")
      conversation = Conversation.create!(assignee: nil, main_participant: user, app: app)

      result = api.send(:add_participant, "", nil, [])
      expect(result).to be_present
    ensure
      conversation&.destroy
      user&.destroy
    end
  end

  describe "send_message with blank profile_id" do
    it "returns nil without sending when profile_id is blank" do
      user = AppUser.create!(email: "d360blank#{SecureRandom.hex(4)}@test.com")
      conversation = Conversation.create!(assignee: nil, main_participant: user, app: app)
      part = instance_double("ConversationPart", private_note?: false)
      message = instance_double("Message")
      allow(part).to receive(:message).and_return(message)
      allow(message).to receive(:as_json).and_return(
        "serialized_content" => { content: [{ type: "text", text: "hi" }] }.to_json
      )

      result = api.send(:send_message, conversation, part)
      expect(result).to be_nil
    ensure
      conversation&.destroy
      user&.destroy
    end
  end
end
