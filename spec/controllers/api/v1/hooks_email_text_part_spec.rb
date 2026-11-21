# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::HooksController do
  describe "#process_email_notification" do
    let(:controller_instance) { described_class.new }

    before do
      allow(controller_instance).to receive(:handle_conversation_part).and_return([nil, nil, nil])
    end

    def build_mail(raw)
      Mail.read_from_string(raw)
    end

    def run_with_mail(raw_email)
      allow(controller_instance).to receive(:read_mail_file).and_return(raw_email)
      json = {
        "receipt" => { "action" => "some_action" },
        "mail" => { "headers" => [] }
      }.to_json
      controller_instance.send(:process_email_notification, json)
    end

    it "calls handle_conversation_part for a text/plain email" do
      raw = <<~EMAIL
        From: sender@example.com
        To: recipient@example.com
        Subject: Test
        Content-Type: text/plain; charset=UTF-8

        Hello world
      EMAIL

      mail = build_mail(raw)
      allow(Mail).to receive(:read_from_string).and_return(mail)
      run_with_mail(raw)

      expect(controller_instance).to have_received(:handle_conversation_part)
    end

    it "does not call handle_conversation_part for multipart/mixed with only text/html" do
      raw = <<~EMAIL
        From: sender@example.com
        To: recipient@example.com
        Subject: Test
        Content-Type: multipart/mixed; boundary="BOUNDARY"

        --BOUNDARY
        Content-Type: text/html; charset=UTF-8

        <p>Hello</p>
        --BOUNDARY--
      EMAIL

      mail = build_mail(raw)
      allow(Mail).to receive(:read_from_string).and_return(mail)
      run_with_mail(raw)

      expect(controller_instance).not_to have_received(:handle_conversation_part)
    end
  end
end
