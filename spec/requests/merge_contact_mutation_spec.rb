# frozen_string_literal: true

require "rails_helper"

RSpec.describe "mergeContact mutation", type: :request do
  let(:project) { FactoryBot.create(:app) }
  let(:agent) do
    project.add_agent({ email: "admin@example.com" }, role_attrs: { access_list: ["manage"], role: "admin" }).agent
  end
  let(:token) { Doorkeeper::AccessToken.create!(resource_owner_id: agent.id, expires_in: 3600) }
  let(:lead) do
    project.add_anonymous_user({}).tap { |visitor| visitor.update_column(:properties, { "plan" => "trial" }) }
  end
  let(:contact) { project.add_user(email: "known@example.com") }

  # Some specs leave ActiveJob inline; the visitor has no email, so an inline
  # chat notification for the opening message would fail before the merge.
  before { ActiveJob::Base.queue_adapter = :test }

  let(:mutation) do
    <<~GRAPHQL
      mutation MergeContact($appKey: String!, $from: String!, $to: String!) {
        mergeContact(appKey: $appKey, from: $from, to: $to) { status }
      }
    GRAPHQL
  end

  def merge(app_key: project.key, from: lead.id.to_s, to: contact.id.to_s)
    post "/graphql",
         params: { query: mutation, variables: { appKey: app_key, from: from, to: to } },
         headers: { "Authorization" => "Bearer #{token.token}" },
         as: :json
  end

  it "merges the lead's conversations and properties into the contact" do
    conversation = project.start_conversation(message: { text_content: "hello" }, from: lead)

    merge

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["errors"]).to be_blank
    expect(response.parsed_body.dig("data", "mergeContact", "status")).to eq("ok")
    expect(conversation.reload.main_participant_id).to eq(contact.id)
    expect(contact.reload.properties).to include("plan" => "trial")
  end

  it "does not merge contacts of an app the agent does not belong to" do
    foreign_app = FactoryBot.create(:app)
    foreign_lead = foreign_app.add_anonymous_user({})
    foreign_contact = foreign_app.add_user(email: "foreign@example.com")
    conversation = foreign_app.start_conversation(message: { text_content: "hi" }, from: foreign_lead)

    merge(app_key: foreign_app.key, from: foreign_lead.id.to_s, to: foreign_contact.id.to_s)

    expect(response.parsed_body.dig("data", "mergeContact")).to be_nil
    expect(conversation.reload.main_participant_id).to eq(foreign_lead.id)
  end
end
