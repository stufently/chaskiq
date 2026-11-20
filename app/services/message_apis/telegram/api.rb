# frozen_string_literal: true

require "rack/mime"

module MessageApis
  module Telegram
    class Api < MessageApis::BasePackage
      def self.definition_info
        {
          name: "Telegram",
          tag_list: ["conversations.added"],
          description: "Interfaces Telegram Messaging",
          icon: "https://logo.clearbit.com/Telegram",
          state: "enabled",
          capability_list: %w[conversations bots],
          definitions: [
            {
              name: "access_token",
              label: "Your Telegram Bot token",
              type: "string",
              required: true,
              grid: { xs: "w-full", sm: "w-full" }
            }
          ]
        }
      end

      include MessageApis::Helpers

      PROVIDER = "telegram"
      RESUMABLE_DELIVERY = true

      attr_accessor :url, :api_key, :conn

      def initialize(config:)
        @api_key = config["api_key"]
        @api_token = config["access_token"]
        @phone = config["user_id"]
        @url = "https://api.telegram.org/bot#{@api_token}"
        @file_url = "https://api.telegram.org/file/bot#{@api_token}"

        @package = config[:package]
        @conn = Faraday.new(
          request: {
            params_encoder: Faraday::FlatParamsEncoder
          }
        )
        @conn.headers = {
          "Content-Type" => "application/json",
          "Accept" => "application/json"
        }
        self
      end

      def register_webhook(app_package, integration)
        data = {
          url: integration.hook_url
        }
        response = @conn.post("#{@url}/setWebhook", data.to_json)
        response.status
      end

      def get_webhook_info
        @conn.get("#{@url}/getWebhookInfo")
      end

      def unregister(app_package, integration)
        # delete_webhooks
      end

      def trigger(event)
        # case event.action
        # when 'email_changed' then register_contact(event.eventable)
        # end
      end

      def process_event(params, package)
        @package = package
        current = params["current"]
        process_message(params, @package) if params.dig("message", "chat").present?
      end

      def get_message_id(response_data)
        response_data.dig("result", "message_id")
      end

      def send_message(conversation, part)
        return if part.private_note?

        message = part.message.as_json
        content = message["serialized_content"]
        if content.blank?
          text = Loofah.fragment(message["html_content"].to_s).to_text(encode_special_chars: false).strip
          return if text.blank?

          content = MessageApis::BlockManager.serialized_text(text)
        end

        begin
          blocks = MessageApis::BlockManager.get_blocks(content)
          return unless blocks.is_a?(Array) && blocks.present?

          plain_message = MessageApis::BlockManager.plain_text(blocks)
        rescue JSON::ParserError, TypeError, NoMethodError
          return
        end

        channel_id = conversation
                     .conversation_channels
                     .find_by(provider: "telegram")
                     &.provider_channel_id

        # TODO: maybe handle an error here ?
        return if channel_id.blank?

        media_methods = {
          "ImageBlock" => ["sendPhoto", :photo],
          "VideoBlock" => ["sendVideo", :video],
          "FileBlock" => ["sendDocument", :document],
          "AudioRecorderBlock" => ["sendAudio", :audio]
        }
        send_text = ->(text) { @conn.post("#{@url}/sendMessage", { chat_id: channel_id, text: text }.to_json) }
        attachments = MessageApis::BlockManager.media_blocks(blocks)
        MessageApis::BlockManager.deliver_attachments(
          attachments, plain_message, send_text: send_text, **delivery_hooks(conversation, part)
        ) do |type, url, caption|
          method, field = media_methods.fetch(type)
          data = { field => url }
          data[:caption] = caption if caption
          upload_telegram(channel_id, data, method: method)
        end
      end

      def get_profile_for_participant(conversation)
        conversation.main_participant
                    &.external_profiles
                    &.find_by(provider: PROVIDER)
                    &.profile_id
      end

      def get_media(id)
        response = @conn.get(
          "#{@url}/getFile?file_id=#{id}"
        )

        # return nil unless response.success?
        params = JSON.parse(response.body)
        file_path = params["result"]["file_path"]
        response = @conn.get(
          "#{@file_url}/#{file_path}"
        )

        response.body
      end

      def handle_direct_upload(id, content_type = nil)
        file_string = get_media(id)
        file_io = StringIO.new(file_string)
        mime = content_type || Marcel::MimeType.for(file_io)
        mime = mime.split(";").first
        extension = Rack::Mime::MIME_TYPES.invert[mime].to_s

        direct_upload(
          file: file_io,
          filename: "#{id}#{extension}",
          content_type: content_type || "image/jpeg"
        )
      end

      def process_message(params, package)
        @package = package

        app = package.app

        message = params["message"]

        sender_id = message["from"]["id"]
        message_id = message["message_id"]

        # determine the id of the user (channel)
        is_agent = sender_id == package.user_id.to_s

        channel_id = message["chat"]["id"] # sender_id
        dialog_user = sender_id

        conversation = find_conversation_by_channel(channel_id.to_s)

        return if conversation && conversation.conversation_part_channel_sources
                                              .find_by(message_source_id: message_id.to_s).present?

        text = message["text"]

        serialized_content = serialize_content(message)

        participant = add_participant(params["message"]["from"], message)

        if conversation.blank?
          conversation = app.conversations.create(
            main_participant: participant,
            conversation_channels_attributes: [
              {
                provider: PROVIDER,
                provider_channel_id: channel_id
              }
            ]
          )
        end

        # TODO: serialize message
        conversation.add_message(
          from: is_agent ? @package.app.agents.first : participant, # agent_required ? Agent.first : participant,
          message: {
            html_content: text,
            serialized_content: serialized_content
          },
          provider: PROVIDER,
          message_source_id: message_id,
          check_assignment_rules: true
        )
      end

      def find_conversation_by_channel(channel)
        conversation = @package
                       .app
                       .conversations
                       .joins(:conversation_channels)
                       .where(
                         "conversation_channels.provider = ? AND
                          conversation_channels.provider_channel_id = ?",
                         PROVIDER, channel
                       ).first
      end

      def serialize_content(data)
        if (text = data["text"]) && text
          text_block(text) if text.present?
        else
          attachment_block(data)
        end
      end

      def attachment_block(data)
        {
          blocks: [media_block(data)],
          entityMap: {}
        }.to_json
      end

      def media_block(data)
        if (k = data.keys & %w[sticker animation video voice document photo]) && k.any?
          f = data[k.first]
          case k.first
          when "sticker", "animation", "video"
            file = handle_direct_upload(f["file_id"], f["mime_type"])
            gif_block(url: file[:url], text: f["file_name"])
          when "voice", "document"
            file = handle_direct_upload(f["file_id"], f["mime_type"])
            file_block(url: file[:url], text: f["file_name"])
          else "photo"
               f = data[k.first].first
               file = handle_direct_upload(f["file_id"], f["mime_type"])
               photo_block(url: file[:url], text: f["file_name"])
          end
        end
      end

      def add_participant(dialog_user, message)
        app = @package.app

        return unless dialog_user

        profile_data = {
          name: "#{dialog_user['first_name']} #{dialog_user['last_name']}"
        }

        data = {
          properties: profile_data
        }

        external_profile = app.external_profiles.find_by(
          provider: PROVIDER,
          profile_id: dialog_user["id"]
        )

        participant = external_profile&.app_user

        ## todo: check user for this & previous conversation
        if participant.blank?
          participant = app.add_anonymous_user(data)
          participant.external_profiles.create(
            provider: PROVIDER,
            profile_id: dialog_user["id"]
          )
        end

        participant
      end

      def upload_telegram(channel_id, data, method: "sendPhoto")
        params = data.merge({ chat_id: channel_id }).to_json
        @conn.post("#{@url}/#{method}", params)
      end
    end
  end
end
