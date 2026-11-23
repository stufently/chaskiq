# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicationCable::Connection, type: :channel do
  let(:app) { FactoryBot.create(:app) }
  let(:agent) { app.add_agent({ email: "agent@example.com" }).agent }

  def token_for(owner, **attrs)
    Doorkeeper::AccessToken.create!(resource_owner_id: owner.id, expires_in: 1.hour.to_i, **attrs).token
  end

  before do
    allow(Chaskiq::Config).to receive(:get).and_call_original
    allow(Chaskiq::Config).to receive(:get).with("AUTH0_ENABLED").and_return(nil)
  end

  it "connects an agent with a valid access token" do
    connect "/cable", params: { app: app.key, token: token_for(agent) }

    expect(connection.current_user).to eq(agent)
    expect(connection.app).to eq(app)
  end

  it "rejects a revoked access token" do
    token = token_for(agent, revoked_at: 1.minute.ago)

    expect { connect "/cable", params: { app: app.key, token: token } }.to have_rejected_connection
  end

  it "rejects an expired access token" do
    token = token_for(agent, created_at: 2.hours.ago)

    expect { connect "/cable", params: { app: app.key, token: token } }.to have_rejected_connection
  end

  it "rejects an unknown access token" do
    expect { connect "/cable", params: { app: app.key, token: "nope" } }.to have_rejected_connection
  end
end
