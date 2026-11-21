# frozen_string_literal: true

require "rails_helper"

RSpec.describe MessageApis::AuditsReports::Api, type: :service do
  let(:app) { FactoryBot.create(:app) }
  let(:agent) { app.add_agent({ email: "agent@test.cl" }).agent }

  describe "#report events_table" do
    it "returns audits ordered by id desc" do
      integration = double("integration", app: app)

      audit1 = Audit.create!(agent: agent, app: app, action: :start_conversation, auditable: agent)
      audit2 = Audit.create!(agent: agent, app: app, action: :close_conversation, auditable: agent)

      api = described_class.allocate
      result = api.report("events_table", integration, { page: 1 })

      ids = result[:collection].pluck("id")
      expect(ids).to eq([audit2.id, audit1.id])
    end
  end
end
