# frozen_string_literal: true

require "rails_helper"

RSpec.describe MessageApis::Dialog360::Api do
  let(:app) { FactoryBot.create(:app) }
  let(:config) do
    { "api_key" => "test", "api_secret" => "secret", "user_id" => "+15551234567",
      "sandbox" => true, :package => OpenStruct.new(app: app) }
  end
  let(:api) { described_class.new(config: config) }

  after { app.destroy }

  describe "process_statuses with read status (M060)" do
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

  describe "prepare_initiator_channel_for with blank profile_id (M061)" do
    it "rolls back and creates no conversation channel" do
      user = AppUser.create!(email: "d360rb#{SecureRandom.hex(4)}@test.com")
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

  describe "add_participant with empty string sender (M062)" do
    it "creates a participant for empty string (truthy, not blank)" do
      result = api.send(:add_participant, "", nil, [])
      expect(result).to be_present
      expect(result).to be_a(AppUser)
    end
  end

  describe "send_message with blank profile_id (M237)" do
    it "returns nil without making HTTP requests when profile_id is blank" do
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
      expect(WebMock).not_to have_requested(:post, /360dialog/)
    ensure
      conversation&.destroy
      user&.destroy
    end
  end
end
