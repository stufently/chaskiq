# frozen_string_literal: true

require "rails_helper"

RSpec.describe ActionTrigger do
  let(:app) { FactoryBot.create(:app) }
  let!(:bot_agent) { app.add_agent({ email: "bot@test.com", name: "Bot" }, bot: true).agent }
  let(:user) { app.add_user(email: "user@example.com") }

  def make_bot_message(conversation, trigger_id: "t1", step_id: "s1")
    conversation.add_message(
      from: bot_agent,
      trigger_id: trigger_id,
      step_id: step_id,
      message: { html_content: "hello", text_content: "hello" }
    )
  end

  describe ".trigger_step" do
    let(:conversation) { app.conversations.create!(main_participant: user) }
    let!(:message) { make_bot_message(conversation) }
    let(:data) do
      {
        "conversation_key" => conversation.key,
        "message_key" => message.key,
        "step" => "1",
        "trigger" => "request_for_email",
        "reply" => nil
      }
    end

    it "adds a bot message when the factory path has a message at the step" do
      trigger = double("trigger", id: 1)
      path = {
        "steps" => [
          { "step_uid" => "1", "messages" => [{ html_content: "hi", serialized_content: "{}" }], "controls" => nil }
        ]
      }
      allow(ActionTriggerFactory).to receive(:find_task).and_return([trigger, path])

      expect { described_class.trigger_step(data, app, user) }
        .to change { conversation.messages.count }.by(1)
    end

    it "returns early when the factory path is blank" do
      allow(ActionTriggerFactory).to receive(:find_task).and_return([double(id: 1), nil])
      expect { described_class.trigger_step(data, app, user) }
        .not_to(change { conversation.messages.count })
    end

    it "propagates the original missing-step error" do
      path = { "steps" => [{ "step_uid" => "other", "messages" => [] }] }
      allow(ActionTriggerFactory).to receive(:find_task).and_return([double(id: 1), path])

      expect { described_class.trigger_step(data, app, user) }.to raise_error(NoMethodError) { |error| expect(error.name).to eq(:[]) }
    end

    context "with a reply on a bot message" do
      before { data["reply"] = { "email" => "new@test.com" } }

      it "calls register_metric when the trigger supports it" do
        trigger = double("trigger", id: 1)
        allow(trigger).to receive(:respond_to?).with(:register_metric).and_return(true)
        path = {
          "steps" => [
            { "step_uid" => "1", "messages" => [{ html_content: "hi", serialized_content: "{}" }], "controls" => nil }
          ]
        }
        allow(ActionTriggerFactory).to receive(:find_task).and_return([trigger, path])
        expect(trigger).to receive(:register_metric).with(
          user,
          data: data["reply"],
          options: hash_including(message_key: message.key, conversation_key: conversation.key)
        )
        described_class.trigger_step(data, app, user)
      end

      it "skips register_metric when the trigger does not support it" do
        trigger = double("trigger", id: 1)
        allow(trigger).to receive(:respond_to?).with(:register_metric).and_return(false)
        path = {
          "steps" => [
            { "step_uid" => "1", "messages" => [{ html_content: "hi", serialized_content: "{}" }], "controls" => nil }
          ]
        }
        allow(ActionTriggerFactory).to receive(:find_task).and_return([trigger, path])
        expect { described_class.trigger_step(data, app, user) }.not_to raise_error
      end
    end

    context "with controls on the step" do
      it "adds a second message with controls" do
        trigger = double("trigger", id: 1)
        path = {
          "steps" => [
            {
              "step_uid" => "1",
              "messages" => [{ html_content: "hi", serialized_content: "{}" }],
              "controls" => { "type" => "data_retrieval" }
            }
          ]
        }
        allow(ActionTriggerFactory).to receive(:find_task).and_return([trigger, path])
        initial_count = conversation.messages.count
        described_class.trigger_step(data, app, user)
        expect(conversation.messages.count).to eq(initial_count + 2)
      end
    end
  end

  describe ".data_submit" do
    it "calls save_replied on the inner message when available" do
      inner = double("inner")
      allow(inner).to receive(:respond_to?).with(:save_replied).and_return(true)
      expect(inner).to receive(:save_replied).with({ "email" => "a@b.com" })
      message = double("message", message: inner)
      described_class.data_submit({ "email" => "a@b.com" }, message)
    end

    it "does nothing when the inner message does not respond to save_replied" do
      inner = double("inner")
      allow(inner).to receive(:respond_to?).with(:save_replied).and_return(false)
      message = double("message", message: inner)
      expect { described_class.data_submit({ "email" => "a@b.com" }, message) }.not_to raise_error
    end
  end

  describe ".process_next_step" do
    let(:conversation) { app.conversations.create!(main_participant: user) }
    let!(:bot_message) { make_bot_message(conversation, step_id: "step_a") }

    it "returns early when trigger_locked has a value" do
      allow(bot_message.trigger_locked).to receive(:value).and_return(1)
      expect { described_class.process_next_step(app, bot_message, user) }
        .not_to(change { conversation.messages.count })
    end

    context "with a factory path" do
      it "adds controls when the next step has no content message" do
        trigger = double("trigger", id: 1)
        path = {
          steps: [
            { step_uid: "step_a", messages: [], controls: nil },
            { step_uid: "step_b", messages: [], controls: { type: "data_retrieval" } }
          ]
        }.with_indifferent_access
        allow(ActionTriggerFactory).to receive(:find_task).and_return([trigger, path])

        expect { described_class.process_next_step(app, bot_message, user) }.to change { conversation.messages.count }.by(1)
        expect(conversation.messages.order(:id).last).to have_attributes(step_id: "step_b", from_bot?: true)
      end

      it "adds the next step message from the path" do
        trigger = double("trigger", id: 1)
        path = {
          "steps" => [
            { "step_uid" => "step_a", "messages" => [], "controls" => nil },
            { "step_uid" => "step_b", "messages" => [{ html_content: "next", serialized_content: "{}" }], "controls" => nil }
          ]
        }
        allow(ActionTriggerFactory).to receive(:find_task).and_return([trigger, path])

        expect { described_class.process_next_step(app, bot_message, user) }.not_to raise_error
      end

      it "reaches the controls branch when next step has controls" do
        trigger = double("trigger", id: 1)
        path = {
          "steps" => [
            { "step_uid" => "step_a", "messages" => [], "controls" => nil },
            {
              "step_uid" => "step_b",
              "messages" => [{ html_content: "next", serialized_content: "{}" }],
              "controls" => { "type" => "data_retrieval" }
            }
          ]
        }
        allow(ActionTriggerFactory).to receive(:find_task).and_return([trigger, path])

        expect { described_class.process_next_step(app, bot_message, user) }.not_to raise_error
      end
    end

    context "without a factory path (static trigger)" do
      it "finds the next step from trigger paths via blocks next_step_uuid" do
        inner_msg = double("inner", blocks: { "next_step_uuid" => "step_b" })
        allow(bot_message).to receive(:message).and_return(inner_msg)

        paths = [
          { steps: [{ step_uid: "step_a", controls: {}, messages: [] }] },
          { steps: [{ step_uid: "step_b", controls: {}, messages: [{ body: "hello" }] }] }
        ]
        trigger = double("trigger", id: 1, paths: paths)
        allow(ActionTriggerFactory).to receive(:find_task).and_return([trigger, nil])

        expect { described_class.process_next_step(app, bot_message, user) }.not_to raise_error
      end
    end
  end

  describe ".handle_follow_actions" do
    let(:conversation) { app.conversations.create!(main_participant: user) }
    let(:message) { double("message", conversation: conversation) }

    it "returns early when follow_actions is blank" do
      path = { "follow_actions" => nil }
      expect { described_class.handle_follow_actions(app, path, message) }.not_to raise_error
    end

    it "delegates each action to process_follow_action" do
      path = { "follow_actions" => [{ "key" => "close" }, { "key" => "assign", "value" => "1" }] }
      expect(described_class).to receive(:process_follow_action).with(app, { "key" => "close" }, message)
      expect(described_class).to receive(:process_follow_action).with(app, { "key" => "assign", "value" => "1" }, message)
      described_class.handle_follow_actions(app, path, message)
    end
  end

  describe ".process_follow_action" do
    let(:conversation) { app.conversations.create!(main_participant: user) }
    let(:message) { double("message", conversation: conversation) }

    it "assigns a user when key is assign and value is present" do
      agent = app.agents.first || app.add_agent({ email: "agent@test.com", first_name: "Agent" }).agent
      action = { "key" => "assign", "value" => agent.id }
      expect(conversation).to receive(:assign_user).with(agent)
      described_class.process_follow_action(app, action, message)
    end

    it "does nothing when assign value is blank" do
      action = { "key" => "assign", "value" => nil }
      expect(conversation).not_to receive(:assign_user)
      described_class.process_follow_action(app, action, message)
    end

    it "does nothing when assign agent is not found" do
      action = { "key" => "assign", "value" => -1 }
      expect(conversation).not_to receive(:assign_user)
      described_class.process_follow_action(app, action, message)
    end

    it "closes the conversation when key is close" do
      action = { "key" => "close" }
      expect(conversation).to receive(:close!)
      described_class.process_follow_action(app, action, message)
    end
  end

  describe ".receive_conversation_part" do
    let(:conversation) { app.conversations.create!(main_participant: user) }
    let!(:bot_message) { make_bot_message(conversation) }
    let(:data) do
      {
        "conversation_key" => conversation.key,
        "message_key" => bot_message.key,
        "submit" => nil,
        "reply" => nil
      }
    end

    it "returns early when the message is already read" do
      bot_message.read!
      allow(described_class).to receive(:process_next_step)
      described_class.receive_conversation_part(app, data, user)
      expect(described_class).not_to have_received(:process_next_step)
    end

    it "skips process_next_step when the message is not from bot" do
      user_message = conversation.add_message(
        from: user,
        message: { html_content: "hi", text_content: "hi" }
      )
      data["message_key"] = user_message.key
      expect(described_class).not_to receive(:process_next_step)
      described_class.receive_conversation_part(app, data, user)
    end

    it "calls process_next_step for bot messages" do
      expect(described_class).to receive(:process_next_step)
      described_class.receive_conversation_part(app, data, user)
    end

    it "calls data_submit when reply is present" do
      data["reply"] = { "email" => "new@test.com" }
      expect(described_class).to receive(:data_submit).with(data["reply"], bot_message)
      allow(described_class).to receive(:process_next_step)
      described_class.receive_conversation_part(app, data, user)
    end
  end
end
