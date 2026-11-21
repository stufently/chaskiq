# frozen_string_literal: true

class Lead < AppUser
  def verify!
    if email.present? && (app_user = app.app_users.find_by(type: "AppUser", email: email))
      clone_records_and_discard(app_user)
    else
      becomes!(AppUser)
      self.type = "AppUser"
      save
    end
  end

  def clone_records_and_discard(app_user)
    attributes = deep_clone.attributes.except("id", "created_at", "updated_at", "session_id")

    verify_event(app_user) if app_user.update(attributes)

    # TODO: detach this
    conversations.each do |c|
      c.main_participant = app_user
      c.save
    end
  end

  def verify_event(app_user)
    events.log(
      action: :verified_lead,
      properties: { from: id, to: app_user.id }
    )

    key = app_user.session_key

    MessengerEventsChannel.broadcast_to(key, {
      type: "user:refresh",
      data: app_user.as_json(only: [:session_id])
    }.as_json)
  end
end
