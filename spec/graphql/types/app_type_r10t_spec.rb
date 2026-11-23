# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::AppType, type: :graphql do
  let(:app) { FactoryBot.create(:app) }
  let(:agent) { app.add_agent({ email: "agent-r10t@example.com" }).agent }
  let(:participant) { app.add_user(email: "user-r10t@example.com") }
  let(:resolver) { described_class.send(:new, app, { current_user: agent }) }
  let(:pagination) { { per: 20, page: 1, filter: nil, sort: nil } }

  before { app.update!(owner_id: agent.id) }

  def start_conversation(text, assignee: nil)
    conversation = app.start_conversation(from: participant, message: { html_content: text })
    conversation.update!(assignee: assignee)
    conversation
  end

  it "filters assigned and unassigned conversations on the same resolver instance" do
    assigned = start_conversation("assigned", assignee: agent)
    unassigned = start_conversation("unassigned")

    expect(resolver.conversations(**pagination, agent_id: agent.id.to_s).map(&:id)).to eq([assigned.id])
    expect(resolver.conversations(**pagination, agent_id: "0").map(&:id)).to eq([unassigned.id])
  end

  it "sorts and paginates only conversations with messages" do
    first = start_conversation("first")
    start_conversation("second")
    app.conversations.create!(main_participant: participant)

    conversations = resolver.conversations(**pagination, page: 2, per: 1, sort: "unfiltered")

    expect(conversations.map(&:id)).to eq([first.id])
  end

  it "still applies the tag filter after selecting an agent" do
    tagged = start_conversation("tagged", assignee: agent)
    start_conversation("untagged", assignee: agent)
    tagged.tag_list.add("selected")
    tagged.save!

    conversations = resolver.conversations(**pagination, agent_id: agent.id.to_s, tag: "selected")

    expect(conversations.map(&:id)).to eq([tagged.id])
  end

  it "rejects unknown Ruby keyword arguments" do
    expect { resolver.conversations(**pagination, unsupported: true) }.to raise_error(ArgumentError, "unknown keyword: :unsupported")
  end

  it "passes GraphQL field arguments to the resolver" do
    assigned = start_conversation("assigned", assignee: agent)
    start_conversation("unassigned")
    query = <<~GRAPHQL
      query AppConversations($key: String!, $agent: String!) {
        app(key: $key) {
          conversations(page: 1, filter: null, sort: "unfiltered", agentId: $agent) {
            collection { key }
          }
        }
      }
    GRAPHQL

    result = ChaskiqSchema.execute(
      query,
      variables: { key: app.key, agent: agent.id.to_s },
      context: { current_user: agent, doorkeeper_authorize: -> { true } }
    ).to_h

    expect(result).to eq("data" => { "app" => { "conversations" => { "collection" => [{ "key" => assigned.key }] } } })
  end
end
