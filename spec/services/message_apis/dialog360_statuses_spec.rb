# frozen_string_literal: true

require "rails_helper"
require "webmock"

RSpec.describe MessageApis::Dialog360::Api do
  include WebMock::API

  around do |example|
    WebMock.enable!
    example.run
    WebMock.disable!
  end

  let(:app) { FactoryBot.create(:app) }
  let(:config) do
    { "api_key" => "test", "api_secret" => "secret", "user_id" => "+15551234567",
      "sandbox" => true, :package => OpenStruct.new(app: app) }
  end
  let(:api) { described_class.new(config: config) }

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
    it "raises ActiveRecord::Rollback when profile_id is blank" do
      recipient = app.add_user(email: "d360rb#{SecureRandom.hex(4)}@test.com")
      conversation = app.conversations.create!(main_participant: recipient)
      allow(api).to receive(:add_participant_to_existing_user).and_return(nil)

      expect {
        api.prepare_initiator_channel_for(conversation, config[:package])
      }.to raise_error(ActiveRecord::Rollback)
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
    it "returns nil without sending when profile_id is blank" do
      recipient = app.add_user(email: "d360blank#{SecureRandom.hex(4)}@test.com")
      conversation = app.conversations.create!(main_participant: recipient)
      part = instance_double("ConversationPart", private_note?: false)
      message = instance_double("Message")
      allow(part).to receive(:message).and_return(message)
      allow(message).to receive(:as_json).and_return(
        "serialized_content" => { content: [{ type: "text", text: "hi" }] }.to_json
      )

      result = api.send(:send_message, conversation, part)
      expect(result).to be_nil
    end
  end
end
