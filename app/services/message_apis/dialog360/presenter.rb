# frozen_string_literal: true

module MessageApis
  module Dialog360
    class Presenter
      # Initialize flow webhook URL
      # Sent when an app has been inserted into a conversation, message or the home screen, so that you can render the app.
      def self.initialize_hook(_params)
        definitions = []
        {
          kind: "initialize",
          definitions: definitions,
          values: {}
        }
      end

      # Submit flow webhook URL
      # Sent when an end-user interacts with your app, via a button, link, or text input. This flow can occur
      # multiple times as an end-user interacts with your app.
      def self.submit_hook(_params)
        definitions = []
        {
          kind: "submit",
          definitions: definitions,
          values: {}
        }
      end

      def self.search_participant(ctx:)
        api = ctx[:package].message_api_klass

        definitions = [
          {
            type: "input",
            id: "unsaved-2",
            name: "search_contact",
            label: "Search contact by email, name or phone",
            placeholder: "Search for a contact...",
            save_state: "unsaved",
            action: {
              type: "submit"
            }
          },
          {
            type: "spacer",
            size: "m"
          }
        ]

        if (term = ctx.dig("values", "search_contact")) && term.present?

          query_term = :last_name_or_first_name_or_name_or_email_or_phone_or_external_profiles_profile_id_i_cont_any
          items = ctx[:package].app.app_users.limit(15).ransack(
            query_term => term
          ).result

          collection = items.map do |c|
            {
              type: "item",
              id: c.id,
              name: "selected-user",
              title: "#{c.type}: #{c.display_name} #{c.email}",
              subtitle: "Phone: #{c.phone} | #{api.get_profile_for_participant_label(c)}",
              action: { type: "submit" }
            }
          end

          if collection.any?
            definitions << {
              type: "list",
              disabled: false,
              items: collection
            }
          end
        end

        # Rails.logger.info definitions

        {
          definitions: definitions
        }
      end

      # Configure flow webhook URL (optional)
      # Sent when a teammate wants to use your app, so that you can show them configuration options before it’s
      # inserted. Leaving this option blank will skip configuration.
      #
      # Steps of the template wizard: pick a contact (search_participant) unless the conversation or the
      # contact is known, list the approved templates (paginated), fill the parameters of the picked
      # template (submit-template), send it (pick-template).
      TEMPLATE_STEPS = {
        "submit-template" => :submit_template_response,
        "pick-template" => :pick_template_response
      }.freeze
      TEMPLATES_PER_PAGE = 10

      def self.configure_hook(kind:, ctx:)
        offset_page = template_offset(ctx)
        return search_participant(ctx: ctx) if participant_missing?(ctx)

        api = ctx[:package].message_api_klass
        templates = JSON.parse(api.retrieve_templates(offset: offset_page))
        return templates_error_response(kind, templates) if templates.dig("meta", "success") == false

        definitions = templates_definitions(ctx, templates)
        step = TEMPLATE_STEPS[ctx.dig(:field, :name)]
        response = step && send(step, ctx, api, definitions)
        response || { kind: kind, definitions: definitions }
      end

      def self.template_offset(ctx)
        return 0 unless ctx.dig("field", "name") == "paginate-template"

        ctx.dig("field", "id").gsub("paginate-template-", "").to_i
      end

      def self.participant_missing?(ctx)
        ctx[:conversation_key].blank? && ctx.dig("field", "name") != "selected-user" &&
          ctx.dig("values", "selected_user").blank?
      end

      def self.templates_error_response(kind, templates)
        { kind: kind, definitions: [
          { type: "text", text: "Error retrieving templates #{templates.dig('meta', 'developer_message')}" }
        ] }
      end

      def self.templates_definitions(ctx, templates)
        definitions = templates_list_definitions(templates)
        definitions << selected_user_field(ctx.dig("field", "id")) if ctx.dig("field", "name") == "selected-user"
        definitions
      end

      def self.templates_list_definitions(templates)
        buttons = pagination_buttons(templates)
        Rails.logger.debug templates
        [
          {
            type: "text",
            text: "Whatsapp templates",
            style: "header",
            align: "center"
          },
          {
            type: "text",
            text: "Whatsapp templates",
            style: "paragraph",
            align: "center"
          },
          { type: "spacer", size: "xs" },
          { type: "separator" },
          {
            type: "list",
            disabled: false,
            items: template_items(templates)
          },
          *buttons
        ].compact
      end

      def self.pagination_buttons(templates)
        offset = templates["offset"]
        next_page_value = offset + TEMPLATES_PER_PAGE
        next_button = paginate_button(next_page_value, "Next ->") if next_page_value <= templates["total"]
        prev_button = paginate_button(offset - TEMPLATES_PER_PAGE, "<- Prev") unless offset.zero?
        [prev_button, next_button]
      end

      def self.paginate_button(page_value, label)
        {
          type: "button",
          name: "paginate-template",
          id: "paginate-template-#{page_value}",
          variant: "success",
          size: "small",
          align: "center",
          label: label,
          action: {
            type: "submit"
          }
        }
      end

      def self.template_items(templates)
        templates["waba_templates"]
          .select { |o| o["status"] == "approved" }
          .map do |c|
          {
            type: "item",
            id: Base64.encode64(c.to_json),
            name: "submit-template",
            title: "Template Name: #{c['name']}",
            subtitle: "Category: #{c['category']}",
            action: { type: "submit" }
          }
        end
      end

      def self.selected_user_field(value)
        {
          value: value,
          name: "selected_user",
          type: "hidden",
          id: "selected_user"
        }
      end

      # will submit
      def self.submit_template_response(ctx, _api, _definitions)
        return unless ctx.dig(:field, :action, :type) == "submit"

        decoded = JSON.parse(Base64.decode64(ctx.dig(:field, :id)))
        definitions = template_form_definitions(ctx, template_inputs(decoded))
        selected_user = ctx.dig("values", "selected_user")
        definitions << selected_user_field(selected_user) if selected_user.present?
        configure_response(ctx, definitions)
      end

      def self.template_inputs(decoded)
        inputs = []
        decoded["components"].each do |o|
          next if o["text"].blank?

          captures = o["text"].scan(/{{\d}}/)
          next if captures.blank?

          captures.each { |c| inputs << template_parameter_input(c) }
          inputs << { type: "spacer", size: "m" }
          inputs << {
            type: "text",
            text: o["text"].to_s,
            style: "muted"
          }
        end
        inputs
      end

      def self.template_parameter_input(capture)
        {
          type: "input",
          id: "unsaved-1",
          label: "parameter: #{capture}",
          placeholder: capture.to_s,
          save_state: "unsaved"
        }
      end

      def self.template_form_definitions(ctx, inputs)
        [
          {
            type: "text",
            text: "Whatsapp template",
            style: "header",
            align: "center"
          },
          {
            type: "text",
            text: ctx.dig(:field, :title),
            style: "muted",
            align: "center"
          },
          { type: "spacer", size: "m" },
          inputs,
          {
            type: "button",
            name: "pick-template",
            id: ctx[:field][:id],
            variant: "success",
            size: "large",
            align: "center",
            label: "confirm",
            action: {
              type: "submit"
            }
          }
        ].flatten
      end

      # will send
      def self.pick_template_response(ctx, api, definitions)
        decoded = JSON.parse(Base64.decode64(ctx.dig(:field, :id)))
        body = api.send_template_message(
          template: decoded,
          selected_user: ctx[:values]["selected_user"],
          conversation_key: ctx[:conversation_key],
          parameters: ctx[:values]["unsaved-1"]
        )
        configure_response(ctx, sent_template_definitions(ctx, decoded, body) || definitions)
      end

      def self.sent_template_definitions(ctx, decoded, body)
        return unless body.is_a?(Hash)
        return template_not_sent_definitions(decoded, body["errors"]) if body["errors"].present?

        template_sent_definitions(ctx, body)
      end

      def self.template_sent_definitions(ctx, body)
        [
          {
            type: "text",
            text: "template sent!",
            style: "header",
            align: "center"
          },
          {
            type: "text",
            text: "you can close this window",
            style: "header",
            align: "center"
          },
          {
            id: "visit-link",
            type: "button",
            label: "Visit conversation",
            action: {
              type: "link",
              url: "/apps/#{ctx['package'].app.key}/conversations/#{body['conversation_key']}"
            },
            align: "center"
          }
        ]
      end

      def self.template_not_sent_definitions(decoded, errors)
        [
          {
            type: "text",
            text: "#{decoded['name']} template NOT sent!",
            style: "header",
            align: "center"
          },
          {
            type: "text",
            text: errors.map { |o| "#{o['code']}: #{o['details']}" }.join("\n"),
            style: "muted",
            align: "center"
          }
        ]
      end

      def self.configure_response(ctx, definitions)
        {
          kind: "configure",
          definitions: definitions,
          results: {
            id: ctx.dig(:field, :id),
            label: ctx.dig(:field, :title)
          }
        }
      end

      private_class_method :template_offset, :participant_missing?, :templates_error_response,
                           :templates_definitions, :templates_list_definitions, :pagination_buttons,
                           :paginate_button, :template_items, :selected_user_field, :submit_template_response,
                           :template_inputs, :template_parameter_input, :template_form_definitions,
                           :pick_template_response, :sent_template_definitions, :template_sent_definitions,
                           :template_not_sent_definitions, :configure_response

      # Submit Sheet flow webhook URL (optional)
      # Sent when a sheet has been submitted. A sheet is an iframe you’ve loaded in the Messenger that is closed
      # and submitted when the Submit Sheets JS method is called.
      def self.sheet_hook(_params)
        { a: 11_111 }
      end

      def self.sheet_view(params); end
    end
  end
end
