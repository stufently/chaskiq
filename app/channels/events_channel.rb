# frozen_string_literal: true

class EventsChannel < ApplicationCable::Channel
  # The stream carries metadata of every conversation of the app (internal
  # notes included), so only agents of that app may subscribe.
  def subscribed
    return reject unless app_agent?

    stream_from "events:#{app.key}"
  end

  def unsubscribed
    # Any cleanup needed when channel is unsubscribed
  end

  def rtc_events(data)
    # @app = App.find_by(key: params[:app])
    conversation = app.conversations.find_by(key: data["conversation_id"])
    return if conversation.blank?

    key = "messenger_events:#{app.key}-#{conversation.main_participant.session_id}"

    if data["event_type"] == "JOIN_ROOM"
      ActionCable.server.broadcast "events:#{app.key}", {
        type: "rtc_events",
        app: app.key,
        event_type: "INIT",
        conversation_id: conversation.key
      }
    end
    ActionCable.server.broadcast key, data
    # ActionCable.server.broadcast "events:#{@app.key}", data
  end

  def receive_conversation_part(data)
    # @app = App.find_by(key: params[:app])
    conversation = app.conversations.find_by(key: data["conversation_key"])
    message = conversation.messages.find_by(key: data["message_key"])
    message.read! if message.authorable_type == "AppUser" # read anyway #!= @app_user
  end

  private

  def app_agent?
    return false unless app.present? && current_user.is_a?(Agent)

    app.owner_id == current_user.id || app.roles.exists?(agent_id: current_user.id)
  end
end
