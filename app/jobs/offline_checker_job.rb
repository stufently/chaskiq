class OfflineCheckerJob < ApplicationJob
  queue_as :default

  def perform(user_id, key)
    return if subscribed?(key)

    u = AppUser.find_by(id: user_id)
    return if u.blank?
    return if u.offline?

    u&.offline!
  end

  private

  def subscribed?(key)
    cable = ActionCable.server.config.cable.symbolize_keys
    return false unless cable[:adapter] == "redis"

    channel = [cable[:channel_prefix], key].compact.join(":")
    redis = Redis.new(url: cable[:url])
    _, count = redis.pubsub("NUMSUB", channel)
    count.positive?
  ensure
    redis&.close
  end
end
