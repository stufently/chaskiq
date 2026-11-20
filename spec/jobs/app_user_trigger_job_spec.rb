# frozen_string_literal: true

require "rails_helper"

RSpec.describe AppUserTriggerJob do
  let(:app) { FactoryBot.create(:app) }
  let(:user) { app.add_user(email: "user@test.cl", first_name: "User") }
  let(:conversation) { app.conversations.create(main_participant: user) }

  let(:message) do
    {
      html_content: "<p>Hello</p>",
      serialized_content: '{"type":"doc"}',
      controls: { "type" => "input" }
    }
  end

  let(:trigger) do
    double(
      "Trigger",
      id: 5,
      paths: [
        {
          "steps" => [
            { "step_uid" => "s1", "messages" => [] },
            { "step_uid" => "s2", "messages" => [message] }
          ]
        }
      ]
    )
  end

  it "adds a message to the conversation with the correct step and trigger" do
    job = described_class.new
    job.instance_variable_set(:@app, app)

    bot = app.agent_bots.first
    expect(conversation).to receive(:add_message).with(
      step_id: "s2",
      trigger_id: 5,
      from: bot,
      message: {
        html_content: "<p>Hello</p>",
        serialized_content: '{"type":"doc"}',
        text_content: "<p>Hello</p>"
      },
      controls: { "type" => "input" }
    )

    job.send(:add_message, trigger, conversation)
  end

  it "raises NoMethodError when paths is empty" do
    job = described_class.new
    job.instance_variable_set(:@app, app)

    empty_trigger = double("Trigger", id: 5, paths: [])
    expect { job.send(:add_message, empty_trigger, conversation) }.to raise_error(NoMethodError)
  end
end
