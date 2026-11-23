# frozen_string_literal: true

module Types
  module AppTypeConversationResolvers
    def conversations(per:, page:, filter:, sort:, agent_id: nil, tag: nil, **)
      term, channel_id = conversation_search_options(**)
      object.blocked?
      object.plan.allow_feature!("Conversations")
      authorize! object, to: :can_read_conversations?, with: AppPolicy

      scope_conversations(filter: filter, channel_id: channel_id, agent_id: agent_id)
      @collection = @collection.page(page).per(per).fast_page
      sort_conversations(sort)
      @collection = @collection.tagged_with(tag) if tag.present?
      @collection = search_conversation_collection(term) if term

      @collection.includes(assignee: { avatar_attachment: :blob }, latest_message: { authorable: { avatar_attachment: :blob } })
    end

    def conversations_counts
      conversations = object.conversations
                            .left_joins(:messages)
                            .where.not(conversation_parts: { id: nil })
                            .distinct

      result = conversations.group("assignee_id").count.dup
      result.merge({
                     all: conversations.size
                   })
    end

    def conversations_tag_counts
      object.conversations.tag_counts.map do |o|
        { tag: o.name, count: o.taggings_count }
      end
    end

    def conversations_channels_counts
      object.conversation_channels.group("provider").count
    end

    def conversation(id:)
      # authorize! object, to: :show?, with: AppPolicy
      authorize! object, to: :can_read_conversations?, with: AppPolicy

      conversation = object.conversations.find_by(key: id)

      conversation.presence&.log_async(action: "conversation_viewed",
                                       user: current_user,
                                       ip: context[:request].remote_ip)

      conversation
    end

    private

    def filter_by_agent(agent_id)
      return @collection.where(assignee_id: nil) if agent_id == "0"

      @collection.where(assignee_id: agent_id)
    end

    def sort_conversations(sort)
      return if sort.blank?

      s = case sort
          when "updated" then "updated_at desc"
          when "newest" then "created_at desc"
          when "oldest" then "updated_at asc"
          when "priority_first" then "priority asc, updated_at desc"
          else
            "id desc"
          end

      if sort != "unfiltered" # && agent_id.blank?
        @collection = @collection.where
                                 .not(latest_user_visible_comment_at: nil)
      end

      @collection = @collection.order(s)
    end

    def conversation_search_options(term: nil, channel_id: nil)
      [term, channel_id]
    end

    def scope_conversations(filter:, channel_id:, agent_id:)
      @collection = object.conversations
                          .left_joins(:messages)
                          .where.not(conversation_parts: { id: nil })
                          .distinct
      @collection = @collection.where(state: filter) if filter.present?

      if channel_id.present?
        @collection = @collection
                      .joins(:conversation_channels)
                      .where("conversation_channels.provider =?", channel_id)
      end

      @collection = filter_by_agent(agent_id) if agent_id.present?
    end

    def search_conversation_collection(term)
      query_fields = %w[
        main_participant_full_name main_participant_name main_participant_email main_participant_postal
        main_participant_phone messages_messageable_of_ConversationPartContent_type_text_content
      ]
      query_term = :"#{query_fields.join('_or_')}_i_cont_any"
      @collection.ransack(query_term => term).result
    end
  end
end
