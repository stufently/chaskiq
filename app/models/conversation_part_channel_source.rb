require "digest"

class ConversationPartChannelSource < ApplicationRecord
  belongs_to :conversation_part

  class StatusEventLockTimeout < StandardError; end

  STATUS_LOCK_TIMEOUT = 5
  STATUS_LOCK_RETRY_INTERVAL = 0.05
  private_constant :STATUS_LOCK_TIMEOUT, :STATUS_LOCK_RETRY_INTERVAL

  def self.with_delivery_lock(part_id, provider, &)
    with_session_lock(["conversation_part_delivery", part_id, provider], wait: false, &)
  end

  def self.with_status_event_lock(conversation_id, event, &)
    identity = ["conversation_status_event", conversation_id, *event.values_at(:provider, :message_source_id, :action)]
    with_session_lock(identity, wait: true, &)
  end

  def self.with_session_lock(identity, wait:, &)
    key = Digest::SHA256.digest(identity.to_json).unpack1("q>")
    with_connection do |connection|
      uncached { hold_session_lock(connection, key, wait, &) }
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
    sql = "SELECT pg_try_advisory_lock(#{key})"
    return connection.select_value(sql) unless wait

    acquire_status_lock(connection, sql)
  end

  def self.acquire_status_lock(connection, sql)
    deadline = monotonic_time + STATUS_LOCK_TIMEOUT
    while monotonic_time < deadline
      return true if connection.select_value(sql)

      remaining = deadline - monotonic_time
      sleep([STATUS_LOCK_RETRY_INTERVAL, remaining].min) if remaining.positive?
    end
    raise StatusEventLockTimeout, "Timed out acquiring status event advisory lock"
  end

  def self.monotonic_time
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def self.release_session_lock(connection, key, completed)
    released = connection.select_value("SELECT pg_advisory_unlock(#{key})")
    Rails.logger.warn("Session advisory lock was lost before unlock") if released == false
  rescue StandardError => e
    # Closing an aborted PostgreSQL session releases its advisory locks.
    connection.throw_away!
    raise if completed

    Rails.logger.error("Session advisory unlock failed with #{e.class}")
  end

  private_class_method :with_session_lock, :hold_session_lock, :acquire_session_lock,
                       :acquire_status_lock, :monotonic_time, :release_session_lock
end
