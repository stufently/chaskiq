require "digest"

class ConversationPartChannelSource < ApplicationRecord
  belongs_to :conversation_part

  def self.with_delivery_lock(part_id, provider)
    key = Digest::SHA256.digest("conversation_part_delivery:#{part_id}:#{provider}").unpack1("q>")

    with_connection do |connection|
      uncached do
        acquired = connection.select_value("SELECT pg_try_advisory_lock(#{key})")
        yield if acquired
      ensure
        connection.select_value("SELECT pg_advisory_unlock(#{key})") if acquired
      end
    end
  end
end
