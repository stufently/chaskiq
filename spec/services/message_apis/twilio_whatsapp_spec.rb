# frozen_string_literal: true

require "rails_helper"

RSpec.describe MessageApis::Twilio::Api do
  let(:config) do
    {
      "api_key" => "test-key",
      "user_id" => "+15551234567",
      :package => nil
    }
  end
  let(:api) { described_class.new(config: config) }

  describe "WhatsApp message sending" do
    it "includes whatsapp: prefix in the From field" do
      conversation = instance_double("Conversation")
      part = instance_double("ConversationPart", private_note?: false)
      message = instance_double("Message")
      allow(part).to receive(:message).and_return(message)
      allow(message).to receive(:as_json).and_return(
        "serialized_content" => { content: [{ type: "paragraph", content: [{ type: "text", text: "hi" }] }] }.to_json
      )

      participant = instance_double("AppUser")
      external_profile = instance_double("ExternalProfile", profile_id: "+15559876543")
      allow(participant).to receive(:external_profiles).and_return(
        instance_double("Association", find_by: external_profile)
      )
      allow(conversation).to receive(:main_participant).and_return(participant)

      stub_request(:post, "https://api.twilio.com/2010-04-01/Accounts/test-key/Messages.json")
        .with(body: hash_including("From" => "whatsapp:+15551234567"))
        .to_return(status: 200, body: '{"sid":"SM123"}')

      api.send(:send_message, conversation, part)

      expect(WebMock).to have_requested(:post, /twilio/)
        .with(body: hash_including("From" => "whatsapp:+15551234567"))
    end
  end
end
