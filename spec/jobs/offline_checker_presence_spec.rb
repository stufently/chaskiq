# frozen_string_literal: true

require "rails_helper"

RSpec.describe OfflineCheckerJob, type: :job do
  let(:app) { FactoryBot.create(:app) }
  let(:user) { app.add_user(email: "presence@example.com").tap(&:online!) }
  let(:key) { "presence:#{app.key}-#{user.session_id}" }
  let(:cable_redis_url) do
    url = URI.parse(ENV.fetch("REDIS_URL"))
    url.path = "/5"
    url.to_s
  end

  before do
    allow(ActionCable.server.config).to receive(:cable).and_return(
      { "adapter" => "redis", "url" => cable_redis_url, "channel_prefix" => "hermes_test" }
    )
    allow(ActionCable.server).to receive(:broadcast)
  end

  it "leaves the user online when another client is still subscribed" do
    first_client = Redis.new(url: cable_redis_url)
    second_client = Redis.new(url: cable_redis_url)
    channel = "hermes_test:#{key}"
    first_client.call("SUBSCRIBE", channel)
    second_client.call("SUBSCRIBE", channel)
    first_client.call("UNSUBSCRIBE", channel)

    # Redis shares subscriptions across logical databases on the same server.
    default_redis = instance_double(Redis, pubsub: [], close: nil)
    allow(default_redis).to receive(:pubsub).with("NUMSUB", channel).and_return([channel, 0])
    allow(Redis).to receive(:new).and_call_original
    allow(Redis).to receive(:new).with(no_args).and_return(default_redis)

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

  it "marks the user offline when only a glob match is subscribed" do
    other_client = Redis.new(url: cable_redis_url)
    other_client.call("SUBSCRIBE", "hermes_test:#{key}-other-za")

    described_class.perform_now(user.id, "#{key}-*?[a]")

    expect(user.reload).to be_offline
  ensure
    other_client&.close
  end
end
