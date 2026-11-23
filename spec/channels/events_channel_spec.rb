# frozen_string_literal: true

require "rails_helper"

RSpec.describe EventsChannel, type: :channel do
  let(:app) { FactoryBot.create(:app) }
  let(:other_app) { FactoryBot.create(:app) }
  let(:agent) { app.add_agent({ email: "member@example.com" }).agent }
  let(:outsider) { other_app.add_agent({ email: "outsider@example.com" }).agent }

  it "streams the project events to an agent of the app" do
    stub_connection(current_user: agent, app: app)

    subscribe

    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_from("events:#{app.key}")
  end

  it "streams the project events to the app owner" do
    owner = Agent.create!(email: "owner@example.com", password: Devise.friendly_token[0, 20])
    app.update!(owner: owner)
    stub_connection(current_user: owner, app: app)

    subscribe

    expect(subscription).to be_confirmed
  end

  it "rejects an agent who belongs to another app" do
    stub_connection(current_user: outsider, app: app)

    subscribe

    expect(subscription).to be_rejected
    expect(subscription.streams).to be_empty
  end

  it "rejects a connection without an agent" do
    stub_connection(current_user: nil, app: app)

    subscribe

    expect(subscription).to be_rejected
  end

  it "rejects a messenger contact of the app" do
    contact = app.add_user(email: "contact@example.com")
    stub_connection(current_user: contact, app: app)

    subscribe

    expect(subscription).to be_rejected
  end

  it "rejects an agent when the connection has no app" do
    stub_connection(current_user: agent, app: nil)

    subscribe

    expect(subscription).to be_rejected
  end
end
