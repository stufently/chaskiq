# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dante::Migrator, ".migrate_conversation_parts" do
  let(:app1) { FactoryBot.create(:app) }
  let(:app2) { FactoryBot.create(:app) }

  let(:draft1) { { "content" => [], "draft" => "one" }.to_json }
  let(:draft2) { { "content" => [], "draft" => "two" }.to_json }

  let(:user1) { app1.add_user(email: "u1@test.com") }
  let(:user2) { app2.add_user(email: "u2@test.com") }

  before do
    app1.start_conversation(
      message: { html_content: "hi", serialized_content: draft1 },
      from: user1
    )
    app2.start_conversation(
      message: { html_content: "hi", serialized_content: draft2 },
      from: user2
    )
  end

  it "converts parts of the own app and leaves the other app untouched" do
    allow(Dante::Converter).to receive(:draftjs_to_prosemirror) { |raw| { "converted" => raw } }

    Dante::Migrator.migrate_conversation_parts(id: app1.id)

    own_parts = ConversationPartContent.joins(
      "INNER JOIN conversation_parts ON conversation_parts.messageable_id = conversation_part_contents.id"
    ).joins(
      "INNER JOIN conversations ON conversations.id = conversation_parts.conversation_id"
    ).where(conversations: { app_id: app1.id })

    other_parts = ConversationPartContent.joins(
      "INNER JOIN conversation_parts ON conversation_parts.messageable_id = conversation_part_contents.id"
    ).joins(
      "INNER JOIN conversations ON conversations.id = conversation_parts.conversation_id"
    ).where(conversations: { app_id: app2.id })

    own_contents = own_parts.map { |p| JSON.parse(p.serialized_content) }
    expect(own_contents).to eq([{ "converted" => draft1 }])

    other_contents = other_parts.map(&:serialized_content)
    expect(other_contents).to eq([draft2])

    expect(Dante::Converter).to have_received(:draftjs_to_prosemirror).once
  end

  it "continues to the next part when the converter raises on one" do
    call_count = 0
    allow(Dante::Converter).to receive(:draftjs_to_prosemirror) do |raw|
      call_count += 1
      raise StandardError, "boom" if call_count == 1

      { "converted" => raw }
    end

    app1.start_conversation(
      message: { html_content: "hi2", serialized_content: { "content" => [], "draft" => "three" }.to_json },
      from: user1
    )

    Dante::Migrator.migrate_conversation_parts(id: app1.id)

    own_parts = ConversationPartContent.joins(
      "INNER JOIN conversation_parts ON conversation_parts.messageable_id = conversation_part_contents.id"
    ).joins(
      "INNER JOIN conversations ON conversations.id = conversation_parts.conversation_id"
    ).where(conversations: { app_id: app1.id }).order(:id)

    contents = own_parts.map(&:serialized_content)
    expect(contents.length).to eq(2)
    expect(JSON.parse(contents[0])).to eq({ "content" => [], "draft" => "one" })
    expect(JSON.parse(contents[1])).to eq({ "converted" => { "content" => [], "draft" => "three" }.to_json })
  end
end
