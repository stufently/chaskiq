# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::HooksController do
  subject(:hooks) { described_class.new }

  describe "#handle_conversation_part" do
    let(:mail) { double(recipients: ["someone@example.com"]) }
    let(:base_headers) do
      [{ "name" => "Subject", "value" => "inbound+x" }]
    end

    before do
      allow(hooks).to receive(:handle_inbound_recipient_from_forwarded).and_return("forwarded_ok")
    end

    it "delegates to handle_inbound_recipient_from_forwarded when X-Forwarded-To starts with inbound+" do
      headers = base_headers + [{ "name" => "X-Forwarded-To", "value" => "inbound+abc@example.com" }]
      json = { "mail" => { "headers" => headers } }

      result = hooks.send(:handle_conversation_part, mail, json)

      expect(result).to eq("forwarded_ok")
      expect(hooks).to have_received(:handle_inbound_recipient_from_forwarded).once.with(mail, "inbound+abc@example.com")
    end

    it "returns nil when X-Forwarded-To does not start with inbound+" do
      headers = base_headers + [{ "name" => "X-Forwarded-To", "value" => "other@example.com" }]
      json = { "mail" => { "headers" => headers } }

      result = hooks.send(:handle_conversation_part, mail, json)

      expect(result).to be_nil
      expect(hooks).not_to have_received(:handle_inbound_recipient_from_forwarded)
    end

    it "returns nil when headers are absent" do
      json = { "mail" => { "headers" => [] } }

      result = hooks.send(:handle_conversation_part, mail, json)

      expect(result).to be_nil
      expect(hooks).not_to have_received(:handle_inbound_recipient_from_forwarded)
    end
  end

  describe "#process_attachment" do
    let(:attachment) { double(filename: "photo.png") }
    let(:uploaded_data) do
      { url: "https://cdn.example.com/photo.png", width: 640, height: 480 }
    end
    let(:img_tag) do
      "<img src='https://cdn.example.com/photo.png' title='photo.png' " \
        "width='640' height='480' />"
    end

    before do
      allow(hooks).to receive(:handle_direct_upload).with(attachment).and_return(uploaded_data)
    end

    it "replaces the inline [image:] pattern with the img tag" do
      message = +"Hi [image: photo.png] there"

      result = hooks.send(:process_attachment, attachment, message)

      expect(result).to eq("Hi #{img_tag} there")
    end

    it "prepends the img tag when the pattern is absent" do
      message = +"Hi"

      result = hooks.send(:process_attachment, attachment, message)

      expect(result).to eq("#{img_tag}Hi")
    end
  end
end
