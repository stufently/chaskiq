# frozen_string_literal: true

module Mutations
  module Conversations
    class StartConversation < Mutations::BaseMutation
      field :conversation, Types::ConversationType, null: false
      argument :app_key, String, required: true
      argument :id, String, required: false, default_value: nil
      argument :message, Types::MessageInputType, required: true
      argument :subject, String, required: false, default_value: nil
      argument :initiator_channel, String, required: false, default_value: nil
      argument :initiator_block, Types::AnyType, required: false, default_value: nil

      def resolve(app_key:, id:, message:, subject:, initiator_channel:, initiator_block:)
        message = message.to_h.with_indifferent_access
        app, author, participant, app_user = resolve_author_and_participant(app_key, id)

        conversation = create_conversation(
          app, author, participant, message, subject, initiator_channel, initiator_block
        )

        handle_reply_mode(conversation, message, app, app_user) if message["reply"].present?

        track_event(conversation, author)

        { conversation: conversation }
      end

      def current_user
        context[:current_user]
      end

      def track_event(conversation, author)
        return unless author.is_a?(Agent)

        conversation.log_async(
          action: "start_conversation",
          user: author,
          ip: context[:request].remote_ip
        )
      end

      private

      def resolve_author_and_participant(app_key, id)
        if current_user.is_a?(Agent)
          resolve_agent_path(app_key, id)
        elsif (app_user = context[:get_app_user].call)
          resolve_app_user_path(app_key, app_user)
        end
      end

      def resolve_agent_path(app_key, id)
        app = current_user.apps.find_by(key: app_key)
        authorize! app, to: :can_manage_conversations?, with: AppPolicy, context: { app: app }
        author = app.agents.where("agents.email =?", current_user.email).first
        participant = app.app_users.find(id)
        [app, author, participant]
      end

      def resolve_app_user_path(app_key, app_user)
        app = App.find_by(key: app_key)
        # TODO: check this, when permit multiple emails, check by different id
        [app, app_user, nil, app_user]
      end

      def create_conversation(app, author, participant, message, subject, initiator_channel, initiator_block)
        options = build_conversation_options(
          author, participant, message, subject, initiator_channel, initiator_block
        )

        # in reply block will create convo without append message
        options = { from: author, participant: participant } if message["reply"].present?

        # creates conversation
        app.start_conversation(options)
      end

      def build_conversation_options(author, participant, message, subject, initiator_channel, initiator_block)
        sanitized_html = ActionController::Base.helpers.strip_tags(message["html"])

        {
          from: author,
          participant: participant,
          initiator_channel: initiator_channel,
          initiator_block: initiator_block,
          subject: subject,
          message: {
            html_content: sanitized_html,
            serialized_content: message[:serialized],
            text_content: message[:text] || ActionController::Base.helpers.strip_tags(message["html"])
          }
        }
      end

      def handle_reply_mode(conversation, message, app, app_user)
        # in reply mode we create separated message
        # maybe we could refactor this an put this into app.start_conversation method
        trigger = app.bot_tasks.find(message["trigger"])
        message_reply = message["reply"]
        first_step = trigger.paths[0]["steps"][0]
        step_uid = first_step["step_uid"]

        reply_message = conversation.add_message(
          step_id: step_uid,
          trigger_id: trigger.id,
          from: app.agent_bots.first,
          controls: first_step["controls"]
        )

        data = message_reply.permit(
          :id, :label, :element, :next_step_uuid
        ).to_h

        reply_message.message.save_replied(data)

        # initialize message
        attributes = build_trigger_attributes(conversation, reply_message)

        ActionTrigger.trigger_step(attributes, app, app_user)
      end

      def build_trigger_attributes(conversation, reply_message)
        {
          conversation_key: conversation.key,
          message_key: reply_message.key,
          trigger: reply_message.trigger_id,
          step: reply_message.messageable.data["next_step_uuid"],
          reply: reply_message.messageable.data
        }.with_indifferent_access
      end
    end
  end
end
