# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::HooksController, type: :controller do
  before do
    allow(MessageApis::SnsMessageVerifier).to receive(:verify!).and_return(true)
    allow(SnsReceiverJob).to receive(:perform_later)
  end

  describe "#process_email_notification" do
    let(:instance) { controller }

    let(:raw_email) do
      <<~EMAIL
        From: sender@example.com
        To: recipient@example.com
        Subject: Test email
        Content-Type: text/plain; charset=UTF-8

        Hello from test
      EMAIL
    end

    let(:sns_message) do
      {
        "receipt" => { "action" => { "bucketName" => "bucket", "objectKey" => "key" } },
        "mail" => { "headers" => [{ "name" => "Message-ID", "value" => "<test@example.com>" }] }
      }.to_json
    end

    before do
      allow(instance).to receive(:read_mail_file).and_return(raw_email)
      allow(Mail).to receive(:read_from_string).and_call_original
    end

    it "parses the JSON message and reads the mail file" do
      allow(instance).to receive(:handle_conversation_part).and_return([nil, nil, nil])
      instance.send(:process_email_notification, sns_message)
      expect(instance).to have_received(:read_mail_file).with({ "bucketName" => "bucket", "objectKey" => "key" })
    end

    it "skips adding a message when body is blank" do
      blank_email = <<~EMAIL
        From: sender@example.com
        To: recipient@example.com
        Subject: Empty
        Content-Type: text/plain; charset=UTF-8

      EMAIL
      allow(instance).to receive(:read_mail_file).and_return(blank_email)
      allow(instance).to receive(:handle_conversation_part).and_return([nil, nil, nil])
      expect { instance.send(:process_email_notification, sns_message) }.not_to raise_error
    end

    it "skips adding a message when recipients are empty" do
      no_recipient_email = <<~EMAIL
        From: sender@example.com
        Subject: No recipient
        Content-Type: text/plain; charset=UTF-8

        Some body text
      EMAIL
      allow(instance).to receive(:read_mail_file).and_return(no_recipient_email)
      allow(instance).to receive(:handle_conversation_part).and_return([nil, nil, nil])
      expect { instance.send(:process_email_notification, sns_message) }.not_to raise_error
    end

    it "calls handle_conversation_part with mail and json_message" do
      mail = Mail.read_from_string(raw_email)
      allow(Mail).to receive(:read_from_string).and_return(mail)
      allow(instance).to receive(:handle_conversation_part).and_return([nil, nil, nil])

      instance.send(:process_email_notification, sns_message)

      expect(instance).to have_received(:handle_conversation_part).with(mail, JSON.parse(sns_message))
    end

    it "does not call add_message when from is blank" do
      allow(instance).to receive(:handle_conversation_part).and_return([nil, nil, nil])
      conversation = double("conversation")
      allow(instance).to receive(:handle_conversation_part).and_return([nil, conversation, nil])
      expect(conversation).not_to receive(:add_message)
      instance.send(:process_email_notification, sns_message)
    end

    it "adds a message to the conversation when from is present" do
      mail = Mail.read_from_string(raw_email)
      allow(Mail).to receive(:read_from_string).and_return(mail)
      from_user = double("from_user")
      conversation = double("conversation")
      allow(instance).to receive(:handle_conversation_part).and_return([nil, conversation, from_user])
      allow(instance).to receive(:process_attachments).and_return("Hello from test")
      allow(instance).to receive(:serialize_content).and_return(nil)

      expect(conversation).to receive(:add_message).with(
        hash_including(
          from: from_user,
          message: hash_including(:serialized_content, :html_content)
        )
      )

      instance.send(:process_email_notification, sns_message)
    end

    it "uses text_block fallback when serialize_content raises" do
      mail = Mail.read_from_string(raw_email)
      allow(Mail).to receive(:read_from_string).and_return(mail)
      from_user = double("from_user")
      conversation = double("conversation")
      allow(instance).to receive(:handle_conversation_part).and_return([nil, conversation, from_user])
      allow(instance).to receive(:process_attachments).and_return("Hello from test")
      allow(instance).to receive(:serialize_content).and_raise(StandardError, "parse error")

      expect(conversation).to receive(:add_message) do |opts|
        expect(opts[:message][:serialized_content]).to be_present
      end

      instance.send(:process_email_notification, sns_message)
    end
  end

  describe "#process_event_notification" do
    let(:instance) { controller }

    it "enqueues SnsReceiverJob with downcased eventType" do
      instance.instance_variable_set(
        :@request_body,
        {
          "Type" => "Notification",
          "Message" => { "eventType" => "Delivery" }.to_json
        }
      )
      instance.send(:process_event_notification)
      expect(SnsReceiverJob).to have_received(:perform_later).with("delivery", { "eventType" => "Delivery" }, anything)
    end

    it "does not enqueue when eventType is blank" do
      instance.instance_variable_set(
        :@request_body,
        {
          "Type" => "Notification",
          "Message" => { "other" => "data" }.to_json
        }
      )
      instance.send(:process_event_notification)
      expect(SnsReceiverJob).not_to have_received(:perform_later)
    end

    it "does not enqueue when message is blank" do
      instance.instance_variable_set(
        :@request_body,
        {
          "Type" => "Notification",
          "Message" => ""
        }
      )
      instance.send(:process_event_notification)
      expect(SnsReceiverJob).not_to have_received(:perform_later)
    end
  end

  describe "#process_notification routing via create" do
    it "routes SES Email Receipt Notification to process_email_notification" do
      body = {
        "Type" => "Notification",
        "MessageId" => SecureRandom.uuid,
        "Subject" => "Amazon SES Email Receipt Notification",
        "Message" => { "receipt" => { "action" => {} }, "mail" => { "headers" => [] } }.to_json
      }
      allow(controller).to receive(:process_email_notification)
      allow(controller).to receive(:reserve_notification).and_return(true)
      allow(controller).to receive(:release_notification)
      post :create, body: body.to_json
      expect(controller).to have_received(:process_email_notification)
    end

    it "routes other notifications to process_event_notification" do
      body = {
        "Type" => "Notification",
        "MessageId" => SecureRandom.uuid,
        "Subject" => "Something else",
        "Message" => { "eventType" => "Bounce" }.to_json
      }
      allow(controller).to receive(:process_event_notification)
      allow(controller).to receive(:reserve_notification).and_return(true)
      allow(controller).to receive(:release_notification)
      post :create, body: body.to_json
      expect(controller).to have_received(:process_event_notification)
    end

    it "skips the SES validation message" do
      body = {
        "Type" => "Notification",
        "MessageId" => SecureRandom.uuid,
        "Subject" => nil,
        "Message" => "Successfully validated SNS topic for Amazon SES event publishing."
      }
      allow(controller).to receive(:process_email_notification)
      allow(controller).to receive(:process_event_notification)
      allow(controller).to receive(:reserve_notification).and_return(true)
      allow(controller).to receive(:release_notification)
      post :create, body: body.to_json
      expect(controller).not_to have_received(:process_email_notification)
      expect(controller).not_to have_received(:process_event_notification)
    end
  end

  describe "notification deduplication via create" do
    it "does not process when reserve_notification returns false" do
      body = {
        "Type" => "Notification",
        "MessageId" => SecureRandom.uuid,
        "Message" => { "eventType" => "Open" }.to_json
      }
      allow(controller).to receive(:reserve_notification).and_return(false)
      allow(controller).to receive(:process_event_notification)
      post :create, body: body.to_json
      expect(controller).not_to have_received(:process_event_notification)
    end

    it "releases the lock when processing fails" do
      body = {
        "Type" => "Notification",
        "MessageId" => SecureRandom.uuid,
        "Message" => { "eventType" => "Open" }.to_json
      }
      allow(controller).to receive(:reserve_notification).and_return(true)
      allow(controller).to receive(:process_notification).and_raise(RuntimeError, "fail")
      allow(controller).to receive(:release_notification)
      expect { post :create, body: body.to_json }.to raise_error(RuntimeError, "fail")
      expect(controller).to have_received(:release_notification)
    end
  end

  describe "#create response" do
    it "returns ok for a non-notification request" do
      post :create, body: { "Type" => "Unknown" }.to_json
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq("ok")
    end
  end

  describe "method visibility" do
    it "process_email_notification is private" do
      expect(Api::V1::HooksController.private_method_defined?(:process_email_notification)).to be true
    end

    it "process_event_notification is private" do
      expect(Api::V1::HooksController.private_method_defined?(:process_event_notification)).to be true
    end

    it "handle_notification is private" do
      expect(Api::V1::HooksController.private_method_defined?(:handle_notification)).to be true
    end

    it "create is public" do
      expect(Api::V1::HooksController.public_method_defined?(:create)).to be true
    end
  end
end
