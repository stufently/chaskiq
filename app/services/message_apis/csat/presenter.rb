# frozen_string_literal: true

module MessageApis
  module Csat
    class Presenter
      # Initialize flow webhook URL
      # Sent when an app has been inserted into a conversation, message or
      # the home screen, so that you can render the app.
      def self.initialize_hook(kind:, ctx:)
        {
          # kind: kind,
          # ctx: ctx,
          wait_for_input: false,
          definitions: [
            csat_buttons
          ]
        }
      end

      # Submit flow webhook URL
      # Sent when an end-user interacts with your app, via a button,
      # link, or text input. This flow can occur multiple times as an
      # end-user interacts with your app.
      def self.submit_hook(kind:, ctx:)
        # return nil if ctx[:current_user].is_a?(Agent)

        data = begin
          JSON.parse(Base64.decode64(ctx[:field][:id]))
        rescue StandardError
          nil
        end

        if data

          c = Conversation.find_by(key: ctx[:conversation_key])

          c.events.create(
            action: "plugins.csat",
            properties: {
              label: data["text"],
              value: data["id"],
              comment: ctx[:values][:label]
            }
          )

          return {
            results: {
              data: {
                label: data["text"],
                value: data["id"]
              },
              comment: ctx[:values][:label]
            },
            definitions: [
              {
                type: "text",
                text: "many thanks!"
              }
            ]
          }

        end

        submit_response(kind, ctx)
      end

      # Configure flow webhook URL (optional)
      # Sent when a teammate wants to use your app, so that you can show
      # them configuration options before it’s inserted. Leaving this option
      # blank will skip configuration.
      def self.configure_hook(kind:, ctx:)
        ctx[:package].message_api_klass
        # conversation_part = ctx[:package].app.conversation_parts.find_by(key: ctx[:conversation_part])

        definitions = [

          # {
          #  type: "input",
          #  id: "label",
          #  label: "CSAT label",
          #  placeholder: "How would you rate your experience with our service?",
          #  save_state: "unsaved"
          # },
          csat_buttons,
          {
            type: "button",
            id: "command-confirm",
            variant: "outlined",
            size: "small",
            align: "center",
            label: "confirm",
            action: {
              type: "submit"
            }
          }
        ]

        if ctx[:field] && ctx[:field]["id"] === "command-confirm"

          return {
            kind: "initialize",
            definitions: [
              csat_buttons
            ]
          }

        end

        {
          kind: kind,
          definitions: definitions
        }
      end

      # Submit Sheet flow webhook URL (optional)
      # Sent when a sheet has been submitted. A sheet is an iframe you’ve loaded in the Messenger that is closed and submitted when the Submit Sheets JS method is called.
      def self.sheet_hook(_params)
        []
      end

      def self.csat_buttons
        {
          type: "single-select",
          id: "checkbox-12",
          align: "center",
          variant: "hovered",
          label: "How would you rate your experience with our service?",
          options: [
            {
              type: "option",
              id: "1",
              text: "😡",
              action: {
                type: "submit"
              }
            },
            {
              type: "option",
              id: "2",
              text: "🙁",
              action: {
                type: "submit"
              }
            },
            {
              type: "option",
              id: "3",
              text: "😐",
              action: {
                type: "submit"
              }
            },
            {
              type: "option",
              id: "4",
              text: "🙂",
              action: {
                type: "submit"
              }
            },
            {
              type: "option",
              id: "5",
              text: "😍",
              action: {
                type: "submit"
              }
            }
          ]
        }
      end

      ###
      def self.submit_response(kind, ctx)
        {
          kind: kind,
          # ctx: ctx,
          definitions: [
            {
              type: "input",
              id: "label",
              label: "CSAT label",
              placeholder: "How would you rate your experience with our service?",
              save_state: "unsaved"
            },
            # {
            #  type: 'text',
            #  text: ctx[:field].to_json
            # },
            {
              type: "button",
              id: Base64.encode64(ctx[:field].to_json),
              name: "command-submit",
              variant: "outlined",
              size: "small",
              align: "center",
              label: "confirm",
              action: {
                type: "submit"
              }
            }
          ]
        }
      end
    end
  end
end
