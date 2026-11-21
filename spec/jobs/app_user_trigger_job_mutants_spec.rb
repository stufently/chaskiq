# frozen_string_literal: true

require "rails_helper"

RSpec.describe AppUserTriggerJob do
  include ActiveSupport::Testing::TimeHelpers

  let(:app) { FactoryBot.create(:app) }
  let(:user) { app.add_user(email: "user@example.com") }
  let(:conversation) { app.conversations.create!(main_participant: user) }
  let(:messages) do
    [
      { "html_content" => "<p>First message</p>" },
      { "html_content" => "<p>Second message</p>" }
    ]
  end
  let(:trigger) do
    app.bot_tasks.create!(
      name: "Welcome bot",
      paths: [{ "steps" => [{ "step_uid" => "welcome", "messages" => messages }] }]
    )
  end

  around do |example|
    # Redis uses the wall clock for expiry, so leave time to inspect the lock after running the job.
    travel_to(1.minute.from_now) { example.run }
  end

  def perform_trigger(conversation_key)
    described_class.new.perform(
      app_key: app.key, user_id: user.id, trigger_id: trigger.id, conversation: conversation_key
    )
  end

  it "adds the first message from the step" do
    perform_trigger(conversation.key)

    part = conversation.messages.find_by!(trigger_id: trigger.id)
    expect(part.message.html_content).to eq("<p>First message</p>")
  end

  it "leaves the conversation untouched while the trigger lock is set" do
    lock = user.trigger_locked
    lock.value = 1

    expect { perform_trigger(conversation.key) }.not_to(change { conversation.messages.count })
  end

  it "sets the trigger lock when processing a trigger" do
    lock = user.trigger_locked

    expect { perform_trigger(conversation.key) }.to change(lock, :value).from(nil).to(be_present)
  end

  it "appends to the conversation identified by the key" do
    key = conversation.key

    expect { perform_trigger(key) }.not_to(change { app.conversations.count })

    expect(conversation.messages.exists?(trigger_id: trigger.id)).to be(true)
  end

  it "starts a conversation assigned to the initiating bot when no key is given" do
    part = perform_trigger(nil)
    new_conversation = part.conversation
    bot = app.agent_bots.first

    expect(new_conversation.initiator).to eq(bot)
    expect(new_conversation.reload).to have_attributes(main_participant: user, assignee: bot)
  end

  after do
    user.trigger_locked.delete
  end
end
