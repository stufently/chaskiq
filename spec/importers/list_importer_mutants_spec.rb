# frozen_string_literal: true

require "rails_helper"
require "roo"

RSpec.describe ListImporter do
  let(:app) { FactoryBot.create(:app) }
  let(:agent) { app.add_agent({ email: "importer@example.com" }).agent }
  let(:spreadsheet) do
    rows = [
      ["email", "name", "last name"],
      ["lead@example.com", "Lead", "One"]
    ]
    Spreadsheet.new(rows)
  end

  around do |example|
    deliveries = ActionMailer::Base.deliveries
    ActionMailer::Base.deliveries = []
    example.run
  ensure
    ActionMailer::Base.deliveries = deliveries
  end

  before do
    allow(Roo::Spreadsheet).to receive(:open).and_return(spreadsheet)
    allow(described_class).to receive(:fetch_model_block).and_return(nil)
  end

  def import_leads(recipient)
    described_class.import("contacts.xlsx", params: { app_id: app.id, agent_id: recipient.id, type: "leads" })
  end

  it "persists the name and the normalized last name from the spreadsheet" do
    import_leads(agent)

    lead = app.app_users.leads.find_by!(email: "lead@example.com")
    expect(lead).to have_attributes(name: "Lead", last_name: "One")
  end

  it "delivers the import notification to the agent who requested the import" do
    agent
    recipient = app.add_agent({ email: "requester@example.com" }).agent
    allow(ImportMailer).to receive(:notify).and_call_original

    expect { import_leads(recipient) }.to change(ActionMailer::Base.deliveries, :size).by(1)

    expect(ImportMailer).to have_received(:notify).with(app: app, agent: recipient).once
    expect(ActionMailer::Base.deliveries.last.to).to eq([recipient.email])
  end
end
