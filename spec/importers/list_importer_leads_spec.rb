# frozen_string_literal: true

require "rails_helper"
require "roo"

RSpec.describe "ListImporter leads" do
  let(:app) do
    App.create(name: "foo", domain_url: "http://ggg.cc")
  end

  let(:agent) do
    app.add_agent({ email: "test@test.cl", first_name: "dsdsa" }).agent
  end

  let(:spreadsheet_data) do
    [
      ["email", "name", "last name"],
      ["lead1@example.com", "Lead", "One"],
      ["lead2@example.com", "Lead", "Two"]
    ]
  end

  before do
    allow(Roo::Spreadsheet).to receive(:open).at_least(:once).and_return(Spreadsheet.new(spreadsheet_data))
    ListImporter.instance_variable_set(:@fetch_model_block, nil)
    ListImporter.instance_variable_set(:@sheet_index, nil)
    ListImporter.transactional(false)
  end

  it "imports two rows as Lead contacts when type is leads" do
    expect do
      ListImporter.import("/dummy/file", params: { app_id: app.id, agent_id: agent.id, type: "leads" })
    end.to change(Lead, :count).by(2)

    expect(Lead.find_by(email: "lead1@example.com")).to be_present
  end

  it "imports as AppUser with an import tag when type is absent" do
    expect do
      ListImporter.import("/dummy/file", params: { app_id: app.id, agent_id: agent.id })
    end.to change(AppUser, :count).by(2)

    user = AppUser.find_by(email: "lead1@example.com")
    expect(user.type).to eq("AppUser")
    expect(user.tag_list.first).to start_with("import ")
  end
end
