# frozen_string_literal: true

require "rails_helper"

RSpec.describe Audit, type: :model do
  let(:app) { FactoryBot.create(:app) }
  let(:agent) { app.add_agent({ email: "agent@example.com", name: "Agent Smith" }).agent }

  describe "#agent_name" do
    it "returns an empty string when the audit has no agent" do
      expect(described_class.new.agent_name).to eq("")
    end
  end

  describe "#serialize_properties" do
    it "uses an app user's display name in the link" do
      user = app.add_user(email: "ada@example.com", first_name: "Ada", last_name: "Lovelace")
      audit = described_class.new(agent: agent, auditable: user)
      link = "[Ada Lovelace](/apps/#{app.key}/users/#{user.id})"

      expect(audit.serialize_properties(app)[:auditable_link]).to eq(link)
    end

    it "includes the agent name and serialized action data" do
      data = { "priority" => 1 }
      audit = described_class.new(agent: agent, auditable: agent, data: data)

      expect(audit.serialize_properties(app)).to include("agent_name" => "Agent Smith", "sdata" => data.to_json)
    end
  end

  describe "#sdata" do
    it "returns action data as JSON" do
      data = { "priority" => 1 }
      audit = described_class.new(data: data)

      expect(JSON.parse(audit.sdata)).to eq(data)
    end
  end

  it "persists the app of the audited conversation" do
    user = app.add_user(email: "visitor@example.com")
    conversation = app.start_conversation(message: { text_content: "Hello" }, from: user)
    audit = described_class.create!(agent: agent, auditable: conversation, action: "start_conversation")

    expect(audit.reload.app_id).to eq(app.id)
  end
end
