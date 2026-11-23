# frozen_string_literal: true

class EventsChannel < ApplicationCable::Channel
  # The stream carries metadata of every conversation of the app (internal
  # notes included), so only agents of that app who may read its
  # conversations can subscribe. The app comes from the subscription params
  # (the dashboard keeps one connection when the agent switches apps) and
  # falls back to the connection's app.
  def subscribed
    return reject unless app_agent?

    stream_from "events:#{events_app.key}"
  end

  def unsubscribed
    # Any cleanup needed when channel is unsubscribed
  end

  def rtc_events(data)
    conversation = events_app.conversations.find_by(key: data["conversation_id"])
    return if conversation.blank?

    key = "messenger_events:#{events_app.key}-#{conversation.main_participant.session_id}"

    if data["event_type"] == "JOIN_ROOM"
      ActionCable.server.broadcast "events:#{events_app.key}", {
        type: "rtc_events",
        app: events_app.key,
        event_type: "INIT",
        conversation_id: conversation.key
      }
    end
    ActionCable.server.broadcast key, data
    # ActionCable.server.broadcast "events:#{@app.key}", data
  end

  def receive_conversation_part(data)
    conversation = events_app.conversations.find_by(key: data["conversation_key"])
    message = conversation.messages.find_by(key: data["message_key"])
    message.read! if message.authorable_type == "AppUser" # read anyway #!= @app_user
  end

  private

  def events_app
    return @events_app if defined?(@events_app)

    @events_app = params[:app].present? ? App.find_by(key: params[:app]) : app
  end

  def app_agent?
    target = events_app
    return false unless target.present? && current_user.is_a?(Agent)

    return true if target.owner_id == current_user.id
    return false unless target.roles.exists?(agent_id: current_user.id)

    # Same permission the GraphQL conversation resolvers require: a role
    # without conversation access (e.g. admin_only) must not get the stream.
    AppPolicy.new(target, user: current_user).apply(:can_read_conversations?)
  end
end
