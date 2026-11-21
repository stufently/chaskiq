# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChatNotifierMailer, type: :mailer do
  let(:app) { FactoryBot.create(:app) }
  let(:agent) { app.add_agent({ email: "agent@test.cl" }).agent }
  let(:user) { app.add_user(email: "user@test.cl", first_name: "User") }

  before do
    app.update!(outgoing_email_domain: "mail.example.com")
  end

  describe "#notify References header" do
    it "includes the two most recent email_message_ids in reverse order" do
      conversation = app.start_conversation(
        message: { html_content: "initial" },
        from: user,
        assignee: agent
      )

      conversation.add_message(from: user, message: { html_content: "m1" }, email_message_id: "m1")
      conversation.add_message(from: user, message: { html_content: "m2" }, email_message_id: "m2")
      part3 = conversation.add_message(from: user, message: { html_content: "m3" }, email_message_id: "m3")
      conversation.add_message(from: user, message: { html_content: "no id" })

      mail = described_class.notify(part3)
      references = mail.header["References"].to_s
      expect(references).to eq("<m3> <m2>")
    end
  end
end
