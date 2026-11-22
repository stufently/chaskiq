# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dante::Migrator, ".migrate_bot_tasks" do
  let(:app) { FactoryBot.create(:app) }

  def task(owner, steps)
    owner.bot_tasks.create!(
      title: "Import messages",
      scheduling: "outside_office",
      paths: [{ "id" => "path", "steps" => steps }]
    )
  end

  def message_step(*contents)
    { "type" => "messages", "messages" => contents.map { |value| { "serialized_content" => value } } }
  end

  it "converts only message contents for the selected app and preserves other settings" do
    other_app = FactoryBot.create(:app)
    unchanged = { "type" => "other", "messages" => [{ "serialized_content" => "raw" }] }
    step = message_step("first", "second")
    step["messages"] << { "text" => "no serialized content" }
    own = task(app, [unchanged, step])
    other = task(other_app, [message_step("foreign")])
    allow(Dante::Converter).to receive(:draftjs_to_prosemirror) { |raw| { "converted" => raw } }

    described_class.migrate_bot_tasks(id: app.id)

    converted = message_step('{"converted":"first"}', '{"converted":"second"}')
    converted["messages"] << { "text" => "no serialized content" }
    expect(own.reload.paths.first["steps"]).to eq([unchanged, converted])
    expect(own.scheduling).to eq("outside_office")
    expect(other.reload.paths.first["steps"]).to eq([message_step("foreign")])
    expect(Dante::Converter).to have_received(:draftjs_to_prosemirror).twice
  end

  it "leaves a failed record unchanged and continues with later records" do
    broken = task(app, [message_step("first", "broken")])
    good = task(app, [message_step("good")])
    allow(Dante::Converter).to receive(:draftjs_to_prosemirror) do |raw|
      raise ArgumentError, "invalid fixture" if raw == "broken"

      { "converted" => raw }
    end

    described_class.migrate_bot_tasks(id: app.id)

    expect(broken.reload.paths.first["steps"]).to eq([message_step("first", "broken")])
    expect(good.reload.paths.first["steps"]).to eq([message_step('{"converted":"good"}')])
  end

  it "skips empty paths and a missing app ID" do
    empty = app.bot_tasks.create!(title: "No paths", paths: [])
    existing = task(app, [message_step("unchanged")])
    allow(Dante::Converter).to receive(:draftjs_to_prosemirror)

    expect(described_class.migrate_bot_tasks).to be_nil
    expect(existing.reload.paths.first["steps"]).to eq([message_step("unchanged")])
    existing.destroy!
    described_class.migrate_bot_tasks(id: app.id)

    expect(empty.reload.paths).to eq([])
    expect(Dante::Converter).not_to have_received(:draftjs_to_prosemirror)
  end
end
