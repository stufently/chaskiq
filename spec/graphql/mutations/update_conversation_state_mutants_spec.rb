# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Conversations::UpdateState do
  let(:app) { FactoryBot.create(:app) }
  let(:agent) { app.add_agent({ email: "agent@example.com" }).agent }
  let(:user) { app.add_user(email: "user@example.com") }
  let(:conversation) { app.conversations.create!(main_participant: user) }
  let(:request) { ActionDispatch::TestRequest.create("REMOTE_ADDR" => "203.0.113.12") }
  let(:mutation) do
    described_class.new(object: nil, field: nil, context: { current_user: agent, request: request })
  end

  before do
    app.update!(owner: agent)
    allow(AuditJob).to receive(:perform_later)
  end

  def resolve_state(state)
    mutation.resolve(app_key: app.key, conversation_id: conversation.id, state: state)
  end

  it "logs the close action with the acting agent and request IP" do
    resolve_state("close")

    audit = hash_including(model: conversation, action: "close", user: agent, ip: request.remote_ip)
    expect(AuditJob).to have_received(:perform_later).with(audit).once
  end

  it "logs the reopen action with the acting agent and request IP" do
    conversation.close!
    resolve_state("reopen")

    audit = hash_including(model: conversation, action: "reopen", user: agent, ip: request.remote_ip)
    expect(AuditJob).to have_received(:perform_later).with(audit).once
  end

  it "returns the updated conversation and its empty validation errors" do
    result = resolve_state("close")

    expect(result[:conversation]).to eq(conversation)
    expect(result[:errors]).to be_an(ActiveModel::Errors)
    expect(result[:errors]).to be_empty
  end

  it "leaves the conversation open and skips the audit for a differently cased action" do
    expect { resolve_state("Close") }.not_to raise_error

    expect(conversation.reload.state).to eq("opened")
    expect(AuditJob).not_to have_received(:perform_later)
  end
end
