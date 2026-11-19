require "digest"

class ConversationPartChannelSource < ApplicationRecord
  belongs_to :conversation_part

  def self.with_delivery_lock(part_id, provider, &)
    with_session_lock(["conversation_part_delivery", part_id, provider], wait: false, &)
  end

  def self.with_status_event_lock(conversation_id, event, &)
    identity = ["conversation_status_event", conversation_id, *event.values_at(:provider, :message_source_id, :action)]
    with_session_lock(identity, wait: true, &)
  end

  def self.with_session_lock(identity, wait:, &block)
    key = Digest::SHA256.digest(identity.to_json).unpack1("q>")
    with_connection do |connection|
      uncached { hold_session_lock(connection, key, wait, &block) }
    end
  end

  def self.hold_session_lock(connection, key, wait)
    acquired = acquire_session_lock(connection, key, wait)
    result = yield if acquired
    completed = true
    result
  ensure
    release_session_lock(connection, key, completed) if acquired
  end

  def self.acquire_session_lock(connection, key, wait)
    return connection.select_value("SELECT pg_try_advisory_lock(#{key})") unless wait

    connection.execute("SELECT pg_advisory_lock(#{key})")
    true
  end

  def self.release_session_lock(connection, key, completed)
    connection.select_value("SELECT pg_advisory_unlock(#{key})")
  rescue StandardError => e
    # Closing an aborted PostgreSQL session releases its advisory locks.
    connection.throw_away!
    raise if completed

    Rails.logger.error("Session advisory unlock failed with #{e.class}")
  end

  private_class_method :with_session_lock, :hold_session_lock, :acquire_session_lock, :release_session_lock
end
