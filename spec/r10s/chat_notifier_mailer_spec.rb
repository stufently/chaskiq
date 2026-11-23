# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChatNotifierMailer, type: :mailer do
  let(:app) { FactoryBot.create(:app) }
  let(:agent) { app.add_agent({ email: "agent@test.cl", first_name: "Agent" }).agent }
  let(:user) { app.add_user(email: "user@test.cl", first_name: "User") }

  before do
    app.update!(outgoing_email_domain: "mail.example.com")
    allow(Chaskiq::Config).to receive(:get).and_call_original
    allow(Chaskiq::Config).to receive(:get).with("SNS_CONFIGURATION_SET").and_return("test-ses-config")
    allow(Chaskiq::Config).to receive(:get).with("HOST").and_return("https://app.example.com")
  end

  def create_conversation_with_message(from:, assignee: nil)
    conversation = app.start_conversation(
      message: { html_content: "initial" },
      from: from,
      assignee: assignee
    )
    part = conversation.add_message(from: from, message: { html_content: "hello there" })
    [conversation, part]
  end

  def mail_sent?(mail)
    !mail.message.is_a?(ActionMailer::Base::NullMail)
  end

  describe "headers" do
    it "sets X-SES-CONFIGURATION-SET from config" do
      _conversation, part = create_conversation_with_message(from: user, assignee: agent)

      mail = described_class.notify(part)
      expect(mail.header["X-SES-CONFIGURATION-SET"].to_s).to eq("test-ses-config")
    end

    it "sets X-CHASKIQ-PART-ID to the conversation part id" do
      _conversation, part = create_conversation_with_message(from: user, assignee: agent)

      mail = described_class.notify(part)
      expect(mail.header["X-CHASKIQ-PART-ID"].to_s).to eq(part.id.to_s)
    end

    it "sets In-Reply-To header with the from_email" do
      _conversation, part = create_conversation_with_message(from: user, assignee: agent)

      mail = described_class.notify(part)
      expect(mail.header["In-Reply-To"].to_s).to be_present
    end
  end

  describe "from and to" do
    it "sends to the assignee when the message author is the main_participant" do
      conversation = app.start_conversation(
        message: { html_content: "initial" },
        from: user,
        assignee: agent
      )
      part = conversation.add_message(from: user, message: { html_content: "from user" })

      mail = described_class.notify(part)
      expect(mail.to).to eq([agent.email])
    end

    it "sends to the main_participant when the message author is not the main_participant" do
      conversation = app.start_conversation(
        message: { html_content: "initial" },
        from: user,
        assignee: agent
      )
      part = conversation.add_message(from: agent, message: { html_content: "from agent" })

      mail = described_class.notify(part)
      expect(mail.to).to eq([user.email])
    end

    it "includes the titleized app name in the from field" do
      _conversation, part = create_conversation_with_message(from: user, assignee: agent)

      mail = described_class.notify(part)
      expect(mail[:from].to_s).to include("My App")
    end
  end

  describe "subject" do
    it "uses the app name in the subject" do
      _conversation, part = create_conversation_with_message(from: user, assignee: agent)

      mail = described_class.notify(part)
      expect(mail.subject).to eq("new message from #{app.name}")
    end
  end

  describe "content type and return path" do
    it "sends as text/html" do
      _conversation, part = create_conversation_with_message(from: user, assignee: agent)

      mail = described_class.notify(part)
      expect(mail.content_type).to include("text/html")
    end

    it "sets return_path to the from_email" do
      _conversation, part = create_conversation_with_message(from: user, assignee: agent)

      mail = described_class.notify(part)
      expect(mail.return_path).to be_present
      expect(mail.return_path).to include("@")
    end
  end

  describe "skip conditions" do
    it "does not send when recipient is blank" do
      conversation = app.start_conversation(
        message: { html_content: "initial" },
        from: user
      )
      part = conversation.add_message(from: user, message: { html_content: "from user" })

      mail = described_class.notify(part)
      expect(mail_sent?(mail)).to be false
    end

    it "does not send when the recipient AppUser is unsubscribed" do
      conversation = app.start_conversation(
        message: { html_content: "initial" },
        from: user,
        assignee: agent
      )
      part = conversation.add_message(from: agent, message: { html_content: "from agent" })
      user.unsubscribe!

      mail = described_class.notify(part)
      expect(mail_sent?(mail)).to be false
    end

    it "does not send when the recipient email is blank" do
      conversation = app.start_conversation(
        message: { html_content: "initial" },
        from: user,
        assignee: agent
      )
      part = conversation.add_message(from: agent, message: { html_content: "from agent" })
      allow(user).to receive(:email).and_return("")

      mail = described_class.notify(part)
      expect(mail_sent?(mail)).to be false
    end

    it "does not send when the rendered content is nil" do
      _conversation, part = create_conversation_with_message(from: user, assignee: agent)
      part.messageable.update!(serialized_content: nil, html_content: nil)

      mail = described_class.notify(part)
      expect(mail_sent?(mail)).to be false
    end

    it "does not send when recipient is a bot Agent with deliveries disabled" do
      conversation = app.start_conversation(
        message: { html_content: "initial" },
        from: user,
        assignee: agent
      )
      part = conversation.add_message(from: user, message: { html_content: "from user" })
      agent.update!(bot: true, enable_deliveries: false)

      mail = described_class.notify(part)
      expect(mail_sent?(mail)).to be false
    end
  end

  describe "template selection" do
    it "renders the agent_notify template for Agent recipients" do
      _conversation, part = create_conversation_with_message(from: user, assignee: agent)

      mail = described_class.notify(part)
      expect(mail.body.encoded).to be_present
    end

    it "renders the notify template for AppUser recipients" do
      conversation = app.start_conversation(
        message: { html_content: "initial" },
        from: user,
        assignee: agent
      )
      part = conversation.add_message(from: agent, message: { html_content: "from agent" })

      mail = described_class.notify(part)
      expect(mail_sent?(mail)).to be true
    end
  end

  describe "References header" do
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

  describe "#image_rewrite" do
    it "rewrites local active_storage paths to absolute URLs" do
      _conversation, part = create_conversation_with_message(from: user, assignee: agent)
      part.messageable.update!(
        serialized_content: nil,
        html_content: '<img src="/rails/active_storage/blobs/abc/image.png">'
      )

      mail = described_class.notify(part)
      expect(mail.body.encoded).to include("https://app.example.com/rails/active_storage/")
    end
  end

  describe "#serialized_to_html" do
    it "renders serialized_content through Dante" do
      doc = { type: "doc", content: [{ type: "paragraph", content: [{ type: "text", text: "rendered" }] }] }.to_json
      _conversation, part = create_conversation_with_message(from: user, assignee: agent)
      part.messageable.update!(serialized_content: doc, html_content: nil)

      mail = described_class.notify(part)
      expect(mail.body.encoded).to include("rendered")
    end

    it "does not send for invalid serialized JSON when no html_content fallback" do
      _conversation, part = create_conversation_with_message(from: user, assignee: agent)
      part.messageable.update!(serialized_content: "not-json{{{", html_content: nil)

      mail = described_class.notify(part)
      expect(mail_sent?(mail)).to be false
    end
  end

  describe "author name" do
    it "uses display_name when available" do
      user.update!(first_name: "John", last_name: "Doe")
      _conversation, part = create_conversation_with_message(from: user, assignee: agent)

      mail = described_class.notify(part)
      expect(mail[:from].to_s).to include("John Doe")
    end

    it "uses the generated name when first_name is nil" do
      user.update!(first_name: nil, last_name: nil)
      _conversation, part = create_conversation_with_message(from: user, assignee: agent)

      mail = described_class.notify(part)
      expect(mail[:from].to_s).to be_present
      expect(mail[:from].to_s).to include("My App")
    end
  end
end
