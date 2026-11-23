# frozen_string_literal: true

module AppAgentManagement
  extend ActiveSupport::Concern

  def add_agent(attrs, bot: nil, role_attrs: {})
    email = attrs.delete(:email)
    user = Agent.find_or_initialize_by(email: email)
    # user.skip_confirmation!
    if user.new_record?
      user.password = attrs[:password] || Devise.friendly_token[0, 20]
      user.save
    end

    role = roles.find_or_initialize_by(agent_id: user.id, role: role)
    data = attrs.deep_merge!(properties: user.properties)

    user.assign_attributes(data)
    user.bot = bot
    user.save

    # role.last_visited_at = Time.now
    role.assign_attributes(role_attrs)
    role.save
    role
  end

  def add_bot_agent(attrs)
    add_agent(attrs, bot: true)
  end

  def create_agent_bot
    add_bot_agent(email: "bot@#{id}-chaskiq", name: "chaskiq bot")
  end

  def add_admin(attrs)
    add_agent(
      {
        email: attrs[:email],
        password: attrs[:password]
      },
      bot: nil,
      role_attrs: { access_list: ["manage"], role: "admin" }
    )
  end
end
