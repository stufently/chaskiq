# frozen_string_literal: true

require "rails_helper"

RSpec.describe Audit, type: :model do
  let(:app) { FactoryBot.create(:app) }
  let(:agent) { app.add_agent({ email: "agent@test.cl", name: "Agent Smith" }).agent }

  describe "#agent_name" do
    it "returns agent display name" do
      audit = Audit.create!(agent: agent, auditable: agent, action: "agent_log_in", data: {})
      expect(audit.agent_name).to eq("Agent Smith")
    end

    context "when agent has no name" do
      let(:nameless_agent) { app.add_agent({ email: "noname@test.cl" }).agent }

      it "returns empty string" do
        audit = Audit.create!(agent: nameless_agent, auditable: nameless_agent, action: "agent_log_in", data: {})
        expect(audit.agent_name).to eq("")
      end
    end
  end

  describe "#serialize_properties" do
    it "builds auditable_link and agent_email for agent auditable" do
      audit = Audit.create!(agent: agent, auditable: agent, action: "agent_log_in", data: {})
      result = audit.serialize_properties(app)
      expect(result[:auditable_link]).to eq("[Agent Smith](/apps/#{app.key}/agents/#{agent.id})")
      expect(result[:agent_email]).to eq("[agent@test.cl](/apps/#{app.key}/agents/#{agent.id})")
    end

    it "builds auditable_link for conversation auditable" do
      app_user = app.add_user(email: "user@test.cl")
      conversation = app.start_conversation(message: { text_content: "hi" }, from: app_user)
      audit = Audit.create!(agent: agent, auditable: conversation, action: "start_conversation", data: {})
      result = audit.serialize_properties(app)
      expect(result[:auditable_link]).to eq("[#{conversation.key}](/apps/#{app.key}/conversations/#{conversation.key})")
    end
  end
end
