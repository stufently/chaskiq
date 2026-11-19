# frozen_string_literal: true

require "rails_helper"

RSpec.describe OfflineCheckerJob, type: :job do
  let(:app) { FactoryBot.create(:app) }
  let(:user) { app.add_user(email: "presence@example.com").tap(&:online!) }
  let(:key) { "presence:#{app.key}-#{user.session_id}" }
  let(:redis_url) { ENV.fetch("REDIS_URL") }

  before do
    allow(ActionCable.server.config).to receive(:cable).and_return(
      { "adapter" => "redis", "url" => redis_url, "channel_prefix" => "hermes_test" }
    )
    allow(ActionCable.server).to receive(:broadcast)
  end

  it "leaves the user online when another client is still subscribed" do
    first_client = Redis.new(url: redis_url)
    second_client = Redis.new(url: redis_url)
    channel = "hermes_test:#{key}"
    first_client.call("SUBSCRIBE", channel)
    second_client.call("SUBSCRIBE", channel)
    first_client.close

    described_class.perform_now(user.id, key)

    expect(user.reload).to be_online
  ensure
    first_client&.close
    second_client&.close
  end

  it "marks the user offline when no client is subscribed" do
    expect(user).to be_online

    described_class.perform_now(user.id, key)

    expect(user.reload).to be_offline
  end
end
