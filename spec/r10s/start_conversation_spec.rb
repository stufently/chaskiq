# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Conversations::StartConversation do
  let(:app) { FactoryBot.create(:app) }
  let(:agent) { app.add_agent({ email: "agent@test.cl", first_name: "Agent" }).agent }
  let(:app_user) { app.add_user(email: "user@test.cl", first_name: "User") }

  before do
    app.update!(owner_id: agent.id)
  end

  def build_mutation(current_user:, get_app_user: nil, request: nil)
    described_class.new(
      object: nil,
      field: nil,
      context: {
        current_user: current_user,
        get_app_user: get_app_user || -> {},
        request: request || ActionDispatch::TestRequest.create
      }
    )
  end

  def serialized_doc(text = "hello")
    { type: "doc", content: [{ type: "paragraph", content: [{ type: "text", text: text }] }] }.to_json
  end

  describe "agent path" do
    it "creates a conversation with the agent as author and the app_user as participant" do
      mutation = build_mutation(current_user: agent)

      result = mutation.resolve(
        app_key: app.key,
        id: app_user.id,
        message: { html: "<p>hi</p>", serialized: serialized_doc("hi"), text: "hi" },
        subject: nil,
        initiator_channel: nil,
        initiator_block: nil
      )

      conversation = result[:conversation]
      expect(conversation).to be_persisted
      expect(conversation.initiator).to eq(agent)
      expect(conversation.main_participant).to eq(app_user)
    end

    it "returns the conversation in the result hash" do
      mutation = build_mutation(current_user: agent)

      result = mutation.resolve(
        app_key: app.key,
        id: app_user.id,
        message: { html: "<p>hi</p>", serialized: serialized_doc("hi"), text: "hi" },
        subject: nil,
        initiator_channel: nil,
        initiator_block: nil
      )

      expect(result.keys).to eq([:conversation])
      expect(result[:conversation]).to be_a(Conversation)
    end
  end

  describe "app_user path" do
    it "creates a conversation with the app_user as author and nil participant" do
      mutation = build_mutation(current_user: nil, get_app_user: -> { app_user })

      result = mutation.resolve(
        app_key: app.key,
        id: nil,
        message: { html: "<p>hello</p>", serialized: serialized_doc("hello"), text: "hello" },
        subject: nil,
        initiator_channel: nil,
        initiator_block: nil
      )

      conversation = result[:conversation]
      expect(conversation).to be_persisted
      expect(conversation.initiator).to eq(app_user)
      expect(conversation.main_participant).to eq(app_user)
    end
  end

  describe "message handling" do
    it "strips HTML tags from the html content" do
      mutation = build_mutation(current_user: nil, get_app_user: -> { app_user })
      html_with_tags = "<p>hello <script>alert('x')</script></p>"

      mutation.resolve(
        app_key: app.key,
        id: nil,
        message: { html: html_with_tags, serialized: serialized_doc, text: "hello" },
        subject: nil,
        initiator_channel: nil,
        initiator_block: nil
      )

      message = app.conversations.last.messages.last
      content = message.messageable
      expect(content.html_content).to include("hello")
      expect(content.html_content).not_to include("<script>")
    end

    it "uses stripped html as text_content when text is nil" do
      mutation = build_mutation(current_user: nil, get_app_user: -> { app_user })

      mutation.resolve(
        app_key: app.key,
        id: nil,
        message: { html: "<p>hello</p>", serialized: serialized_doc, text: nil },
        subject: nil,
        initiator_channel: nil,
        initiator_block: nil
      )

      message = app.conversations.last.messages.last
      content = message.messageable
      expect(content.text_content).to eq("hello")
    end

    it "passes serialized content through" do
      mutation = build_mutation(current_user: nil, get_app_user: -> { app_user })
      doc = serialized_doc("test content")

      mutation.resolve(
        app_key: app.key,
        id: nil,
        message: { html: "<p>test content</p>", serialized: doc, text: "test content" },
        subject: nil,
        initiator_channel: nil,
        initiator_block: nil
      )

      message = app.conversations.last.messages.last
      content = message.messageable
      expect(content.serialized_content).to eq(doc)
    end
  end

  describe "reply mode" do
    let(:bot_task) do
      app.bot_tasks.create!(
        title: "test trigger",
        state: "enabled",
        paths: [
          {
            "steps" => [
              { "step_uid" => "step-1", "controls" => { "type" => "ask" } }
            ]
          }
        ]
      )
    end

    before do
      app.update!(outgoing_email_domain: "mail.example.com")
      bot_task
    end

    def resolve_reply(current_user:, id:, get_app_user:)
      mutation = build_mutation(current_user: current_user, get_app_user: get_app_user)
      mutation.resolve(
        app_key: app.key,
        id: id,
        message: {
          html: "<p>initial</p>",
          reply: ActionController::Parameters.new(id: "ctrl-1", label: "Yes", element: "button", next_step_uuid: "step-2"),
          trigger: bot_task.id
        },
        subject: nil,
        initiator_channel: nil,
        initiator_block: nil
      ).fetch(:conversation)
    end

    it "fetches the app user once and passes the same app user to the trigger" do
      provider = -> { app_user }
      expect(provider).to receive(:call).once.and_call_original
      expect(ActionTrigger).to receive(:trigger_step).with(hash_including(step: "step-2"), app, app_user)

      conversation = resolve_reply(current_user: nil, id: nil, get_app_user: provider)

      expect(conversation.messages.count).to eq(1)
    end

    it "passes nil to the trigger for an agent reply without resolving the app user" do
      provider = -> { app_user }
      expect(provider).not_to receive(:call)
      expect(ActionTrigger).to receive(:trigger_step).with(hash_including(step: "step-2"), app, nil)

      conversation = resolve_reply(current_user: agent, id: app_user.id, get_app_user: provider)

      expect(conversation.messages.count).to eq(1)
    end
  end

  describe "track_event" do
    it "logs async when author is an Agent" do
      mutation = build_mutation(current_user: agent)

      expect_any_instance_of(Conversation).to receive(:log_async).with(
        hash_including(action: "start_conversation", user: agent)
      )

      mutation.resolve(
        app_key: app.key,
        id: app_user.id,
        message: { html: "<p>hi</p>", serialized: serialized_doc("hi"), text: "hi" },
        subject: nil,
        initiator_channel: nil,
        initiator_block: nil
      )
    end

    it "does not log when author is an AppUser" do
      mutation = build_mutation(current_user: nil, get_app_user: -> { app_user })

      expect_any_instance_of(Conversation).not_to receive(:log_async)

      mutation.resolve(
        app_key: app.key,
        id: nil,
        message: { html: "<p>hi</p>", serialized: serialized_doc("hi"), text: "hi" },
        subject: nil,
        initiator_channel: nil,
        initiator_block: nil
      )
    end
  end

  describe "subject and channel passthrough" do
    it "passes subject to the conversation" do
      mutation = build_mutation(current_user: nil, get_app_user: -> { app_user })

      result = mutation.resolve(
        app_key: app.key,
        id: nil,
        message: { html: "<p>hi</p>", serialized: serialized_doc("hi"), text: "hi" },
        subject: "Help needed",
        initiator_channel: nil,
        initiator_block: nil
      )

      expect(result[:conversation].subject).to eq("Help needed")
    end
  end
end
