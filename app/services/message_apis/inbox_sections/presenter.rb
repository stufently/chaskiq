# frozen_string_literal: true

module MessageApis
  module InboxSections
    class Presenter
      def self.user_data
        [
          { type: "data-table",
            items: [
              { type: "field-value", field: "Key", value: "Value 1" },
              { type: "field-value", field: "Key", value: "Value 2" },
              { type: "field-value", field: "Key",
                value: "Value 3 which is a very long value that will exhibit different behaviours to the other values" }
            ] }
        ]
      end

      # Initialize flow webhook URL
      # Sent when an app has been inserted into a conversation, message or
      # the home screen, so that you can render the app.
      def self.initialize_hook(kind:, ctx:)
        type_value = ctx.dig(:values, :type)
        block_type = ctx.dig(:values, :block_type)

        if type_value == "content"

          # case ctx.dig(:values, :block_type)
          # when 'tag-blocks'
          # when
          # else
          # end

          return {
            # ctx: ctx,
            values: { block_type: block_type },
            definitions: [
              {
                type: "content"
              }
            ]
          }
        end

        definitions = [
          {
            id: "bubu",
            label: "this is from initialize",
            type: "button",
            action: {
              type: "submit"
            }
          }
        ] + user_data

        {
          # kind: kind,
          # ctx: ctx,
          definitions: definitions
        }
      end

      # Submit flow webhook URL
      # Sent when an end-user interacts with your app, via a button,
      # link, or text input. This flow can occur multiple times as an
      # end-user interacts with your app.
      def self.submit_hook(kind:, ctx:)
        { content: { kind: kind, ctx: ctx } }

        {
          definitions: [
            {
              type: "text",
              text: "success"
            }
          ]
        }
      end

      def self.base_schema
        [

          {
            type: "text",
            text: "Pick a template",
            style: "header"
          },

          {
            type: "list",
            disabled: false,
            items: [
              {
                type: "item",
                id: "user-blocks",
                title: "UserBlock",
                subtitle: "Put some user blocks",
                action: {
                  type: "submit"
                }
              },
              {
                type: "item",
                id: "tag-blocks",
                title: "TagBlocks",
                subtitle: "Put some TagBlocks",
                action: {
                  type: "submit"
                }
              },
              {
                type: "item",
                id: "user-properties-block",
                title: "User Properties",
                subtitle: "Put some ConversationBlock",
                action: {
                  type: "submit"
                }
              },
              {
                type: "item",
                id: "external-profiles",
                title: "External Profiles",
                subtitle: "Put some ConversationBlock",
                action: {
                  type: "submit"
                }
              },
              {
                type: "item",
                id: "assignee-block",
                title: "AssigneeBlock",
                subtitle: "Put some AssigneeBlock",
                action: {
                  type: "submit"
                }
              },
              {
                type: "item",
                id: "conversation-events",
                title: "Conversation Events",
                subtitle: "Put some Events on the sidebar",
                action: {
                  type: "submit"
                }
              }
            ]
          }
        ]
      end

      # Configure flow webhook URL (optional)
      # Sent when a teammate wants to use your app, so that you can show
      # them configuration options before it’s inserted. Leaving this option
      # blank will skip configuration.
      def self.configure_hook(kind:, ctx:)
        definitions = base_schema

        if %w[user-properties-block
              assignee-block
              user-blocks
              tag-blocks
              conversation-block
              assignee-block
              conversation-events
              external-profiles].include? ctx.dig(:field, :id)
          results = {
            url: "/ppupu",
            type: "content",
            block_type: ctx.dig(:field, :id)
          }
          return {
            kind: "initialize",
            definitions: [],
            results: results
          }
        end

        {
          kind: kind,
          # ctx: ctx,
          definitions: definitions
        }
      end

      # Blocks of content_hook by values[:block_type]. A truthy values[:c] replaces an early block with
      # a "foo" text, a late block is built after it and wins (the order of the former if chain).
      EARLY_BLOCKS = {
        "user-blocks" => :user_block,
        "conversation-events" => :events_block,
        "user-properties-block" => :user_properties_block,
        "external-profiles" => :external_profiles_block
      }.freeze
      LATE_BLOCKS = { "assignee-block" => :assignee_block, "tag-blocks" => :tags_block }.freeze
      USER_PROPERTIES = {
        "Last Seen" => lambda do |u|
          I18n.l(u.last_visited_at, format: :short)
        rescue StandardError
          nil
        end,
        "Location" => ->(u) { [u.region, u.city, u.country].compact.join(", ") },
        "Ip" => ->(_u) {},
        "Sessions" => ->(u) { u.web_sessions },
        "Timezone" => ->(_u) {},
        "Browser" => ->(u) { [u.browser, u.browser_version].join(", ") },
        "OS" => ->(u) { [u.os, u.os_version].join(", ") },
        "Language" => ->(u) { u.browser_language },
        "Referrer" => ->(u) { u.referrer }
      }.freeze

      def self.content_hook(kind:, ctx:)
        conversation = Conversation.find_by(key: ctx[:conversation_key])
        user = conversation.main_participant
        block_type = ctx.dig(:values, :block_type)

        definitions = send(EARLY_BLOCKS[block_type], conversation, user) if EARLY_BLOCKS.key?(block_type)
        definitions = [{ text: "foo", type: "text" }] if ctx.dig(:values, :c)
        definitions = send(LATE_BLOCKS[block_type], conversation) if LATE_BLOCKS.key?(block_type)

        { definitions: definitions }
      end

      def self.user_block(conversation, user)
        definitions = [
          { type: "text", text: user.display_name.presence || "---", style: "header", align: "center" },
          { type: "image", url: user.avatar_url, height: 64, width: 64, align: "center", rounded: true }
        ]
        definitions << { type: "text", text: user.email, style: "muted", align: "center" } if user.email.present?
        definitions << { type: "text", text: user.type, style: "muted", align: "center" }
        definitions << visit_button("visit-user-profile", "/apps/#{conversation.app.key}/users/#{user.id}")
      end

      def self.events_block(conversation, _user)
        items = conversation.events.order("events.id asc").map do |e|
          { type: "item", id: "event-#{e.id}", title: e.action, subtitle: I18n.l(e.created_at, format: :short),
            action: { type: "submit" } }
        end
        [{ type: "text", text: "Events", style: "header" }, { type: "list", items: items }]
      end

      def self.user_properties_block(_conversation, user)
        items = USER_PROPERTIES.map { |label, call| { type: "field-value", field: label, value: call.call(user) } }
        [{ type: "text", text: "Contact's browsing properties", style: "header" }, { type: "data-table", items: items }]
      end

      def self.external_profiles_block(_conversation, user)
        tables = user.external_profiles.map do |o|
          { type: "data-table",
            items: [{ type: "field-value", field: "Name", value: o["provider"] },
                    { type: "field-value", field: "External id", value: o["profile_id"] }] }
        end
        tables = { type: "text", text: "no external profiles found", style: "muted", align: "center" } if tables.empty?
        [{ type: "text", text: "Contact's External profiles", style: "header" }, tables].flatten
      end

      def self.assignee_block(conversation)
        assignee = conversation&.assignee
        definitions = [{ type: "text", text: "Assignee", style: "header" }]
        return definitions << { text: "unassigned", type: "text", style: "muted", align: "center" } if assignee.blank?

        name = assignee&.display_name&.empty? ? assignee.email : assignee.display_name
        definitions << { text: name, type: "text" }
        definitions << visit_button("visit-agent-profile", "/apps/#{conversation.app.key}/agents/#{assignee.id}")
      end

      def self.tags_block(conversation)
        tags = if conversation.tag_list.any?
                 { text: conversation.tag_list.join(", "), type: "text" }
               else
                 { text: "no tags found", type: "text", style: "muted", align: "center" }
               end
        [{ text: "Conversation Tags", type: "text", style: "header" }, tags]
      end

      def self.visit_button(id, url)
        { id: id, label: I18n.t("common.visit"), type: "button", variant: "link", align: "right",
          action: { type: "link", url: url } }
      end

      private_class_method :user_block, :events_block, :user_properties_block, :external_profiles_block,
                           :assignee_block, :tags_block, :visit_button

      # Submit Sheet flow webhook URL (optional)
      # Sent when a sheet has been submitted. A sheet is an iframe you’ve loaded in the Messenger that is closed
      # and submitted when the Submit Sheets JS method is called.
      def self.sheet_view(params); end
    end
  end
end
