# frozen_string_literal: true

class ActionTrigger
  def self.trigger_step(data, app, current_user)
    conversation = app.conversations.find_by(key: data["conversation_key"])
    message = conversation.messages.find_by(key: data["message_key"])

    trigger, path = ActionTriggerFactory.find_task(
      data: data,
      app: app,
      app_user: current_user
    )

    return if path.blank?

    next_step = find_step(path, data["step"])

    author = app.agent_bots.first
    content = next_step["messages"].first
    add_step_message(conversation, next_step, trigger, author, content) if content.present?
    handle_trigger_step_reply(trigger, current_user, message, conversation, data)

    return if next_step["controls"].blank?

    conversation.add_message(
      step_id: next_step[:step_uid],
      trigger_id: trigger.id,
      from: author,
      controls: next_step["controls"]
    )
  end

  def self.data_submit(data, message)
    message.message.save_replied(data) if message.message.respond_to?(:save_replied)
  end

  def self.process_next_step(app, message, current_user)
    return if message.trigger_locked.value.present?

    message.trigger_locked.value = 1

    trigger, path = ActionTriggerFactory.find_task(
      data: {
        "step" => message.step_id,
        "trigger" => message.trigger_id
      },
      app: app,
      app_user: current_user
    )

    next_step = resolve_next_step(path, trigger, message)

    if next_step.blank?
      handle_follow_actions(app, path, message)
      return
    end

    author = app.agent_bots.first
    content = next_step["messages"].first
    message = add_step_message(message.conversation, next_step, trigger, author, content) if content.present?

    return if next_step["controls"].blank?

    message.conversation.add_message(
      step_id: next_step[:step_uid],
      trigger_id: trigger.id,
      from: author,
      controls: next_step["controls"]
    )
  end

  def self.handle_follow_actions(app, path, message)
    follow_actions = path["follow_actions"]
    return if follow_actions.blank?

    follow_actions.each do |action|
      process_follow_action(app, action, message)
    end
  end

  def self.process_follow_action(app, action, message)
    conversation = message.conversation
    case action["key"]
    when "assign"
      return if action["value"].blank?

      agent = app.agents.find_by(id: action["value"])
      return if agent.blank?

      conversation.assign_user(agent)
    when "close"
      conversation.close!
    end
  end

  def self.receive_conversation_part(app, data, current_user)
    conversation = app.conversations.find_by(key: data["conversation_key"])
    message = conversation.messages.find_by(key: data["message_key"])

    return if message.read?

    message.read! if message.authorable != current_user

    return unless message.from_bot?

    process_next_step(app, message, current_user)

    #### TODO: to be deprecated in favor of app packages
    if data["submit"].present? && message.message&.blocks&.dig("type") == "data_retrieval"
      opts = app.searcheable_fields_list
      current_user.update(data["submit"].slice(*opts))
      data_submit(data["submit"], message)
    end

    data_submit(data["reply"], message) if data["reply"].present?
  end

  class << self
    private

    def find_step(path, step_key)
      path["steps"].find { |o| o["step_uid"] == step_key }
    end

    def add_step_message(conversation, step, trigger, author, content)
      conversation.add_message(
        step_id: step[:step_uid],
        trigger_id: trigger.id,
        from: author,
        message: {
          html_content: content[:html_content],
          serialized_content: content[:serialized_content],
          text_content: content[:html_content]
        }
      )
    end

    def handle_trigger_step_reply(trigger, current_user, message, conversation, data)
      return unless message.from_bot? && data["reply"].present?

      data_submit(data["reply"], message)
      return unless trigger.respond_to?(:register_metric)

      trigger.register_metric(
        current_user,
        data: data["reply"],
        options: {
          message_key: message.key,
          conversation_key: conversation.key
        }
      )
    end

    def resolve_next_step(path, trigger, message)
      if path
        next_index = path["steps"].index { |o| o["step_uid"].to_s == message.step_id } + 1
        return path["steps"][next_index]
      end

      paths = trigger.paths.map do |o|
        o[:steps].find do |s|
          step_uid = s[:step_uid].to_s
          blocks = message&.message&.blocks
          step_uid == blocks&.dig("next_step_uuid")
        end
      end
      found = paths.find { |o| o }
      found.with_indifferent_access
    end
  end
end
