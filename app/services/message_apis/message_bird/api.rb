# frozen_string_literal: true

module MessageApis::MessageBird
  class Api < MessageApis::BasePackage
    def self.definition_info
      {
        name: "MessageBird",
        tag_list: ["conversations.added"],
        description: "Interfaces MessageBird Whatsapp",
        icon: "https://logo.clearbit.com/MessageBird.com",
        state: Rails.env.production? ? "disabled" : "enabled",
        definitions: [
          {
            name: "user_id",
            label: "Phone",
            type: "string",
            required: true,
            hint: "The MessageBird Whatsapp number (format: +14155231223)",
            grid: { xs: "w-full", sm: "w-full" }
          },
          {
            name: "api_key",
            label: "Your MessageBird API key",
            type: "string",
            required: true,
            grid: { xs: "w-full", sm: "w-full" }
          },
          {
            name: "sandbox",
            label: "is sandbox",
            type: "checkbox",
            grid: { xs: "w-full", sm: "w-full" }
          }
        ]
      }
    end

    PROVIDER = "message_bird"
    RESUMABLE_DELIVERY = true
    include MessageApis::Helpers

    attr_accessor :url, :api_key, :conn

    def initialize(config:)
      @api_key = config["api_key"]
      @api_token = config["api_secret"]
      @phone = config["user_id"]

      @url = if config["sandbox"]
               "https://whatsapp-sandbox.messagebird.com/v1/"
             else
               "https://conversations.messagebird.com/v1/"
             end

      @conn = Faraday.new(
        request: {
          params_encoder: Faraday::FlatParamsEncoder
        }
      )

      key = "#{'test_' if config['sandbox']}#{@api_key}"

      @conn.headers = {
        authorization: "AccessKey #{key}",
        "Content-Type" => "application/json",
        "Accept" => "application/json"
      }

      self
    end

    def register_webhook(app_package, integration)
      data = {
        url: integration.hook_url,
        events: ["message.created", "message.updated"],
        channelId: integration.id
      }

      response = @conn.post("#{@url}/webhook", data.to_json)
      response.status
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

      process_statuses(params["statuses"]) if params["statuses"].present?

      process_message(params, @package) if params["message"].present?
    end

    def process_statuses(statuses)
      statuses.each do |status|
        case status["status"]
        when "read" then process_read(status["id"])
        else
          Rails.logger.info "no processing for #{status['status']} event"
        end
      end
    end

    def get_message_id(response_data)
      response_data["id"] || response_data.dig("messages", 0, "id")
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

      profile_id = conversation.main_participant
                               &.external_profiles
                               &.find_by(provider: PROVIDER)
                               &.profile_id

      # TODO: maybe handle an error here ?
      return if profile_id.blank?

      media_types = {
        "ImageBlock" => "image", "VideoBlock" => "video", "FileBlock" => "file", "AudioRecorderBlock" => "audio"
      }
      addressing = {
        from: @phone,
        to: profile_id.gsub("+", "")
      }
      post_content = ->(data) { @conn.post("#{@url}send", addressing.merge(data).to_json) }
      send_text = ->(text) { post_content.call(type: "text", content: { text: text }) }
      attachments = MessageApis::BlockManager.media_blocks(blocks)
      MessageApis::BlockManager.deliver_attachments(
        attachments, plain_message, send_text: send_text, **delivery_hooks(conversation, part)
      ) do |block_type, url, caption|
        type = media_types.fetch(block_type)
        data = { url: url }
        data[:caption] = caption if caption
        post_content.call(type: type, content: { type => data })
      end
    end

    # not used fro now
    def mark_as_read(id)
      message_params = {
        status: "read"
      }
      @conn.post(
        "#{@url}/messages/#{id}",
        message_params.to_json
      )
    end

    def get_media(id)
      response = @conn.get(
        "#{@url}/media/#{id}"
      )
      return nil if response.success?

      response.body
    end

    def handle_direct_upload(id, content_type = nil)
      file_string = get_media(id)
      file = StringIO.new(file_string)
      direct_upload(
        file: file,
        filename: "mb-file",
        content_type: content_type || "image/jpeg"
      )
    end

    def process_message(params, package)
      @package = package

      app = package.app

      message = params["message"]

      sender_id = message["from"]
      to = message["to"]
      message_id = message["id"]

      # determine the id of the user (channel)
      is_agent = sender_id == package.user_id.to_s

      channel_id = is_agent ? message["to"] : message["from"]
      dialog_user = sender_id

      conversation = find_conversation_by_channel(channel_id)

      return if conversation && conversation.conversation_part_channel_sources
                                            .find_by(message_source_id: message_id).present?

      text = message.dig("content", "text")

      serialized_content = serialize_content(message)

      participant = add_participant(channel_id, message, params["contact"])

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
                       "conversation_channels.provider =? AND
                          conversation_channels.provider_channel_id =?",
                       PROVIDER, channel
                     ).first
    end

    def serialize_content(data)
      if (text = data.dig("content", "text")) && text
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
      media_type = data["content"].keys.first
      content = data["content"][data["content"].keys.first]
      url = content["url"]
      text = content["caption"]
      case media_type
      when "unsupported" then nil
      when "image"
        file = handle_direct_upload(url["id"], url["mime_type"])
        photo_block(url: file[:url], text: text)
      when "video"
        file = handle_direct_upload(url["id"], url["mime_type"])
        gif_block(url: file[:url], text: text)
      when "audio", "voice", "document"
        file = handle_direct_upload(url["id"], url["mime_type"])
        file_block(url: file[:url], text: text)
      end
    end

    def add_participant(channel_id, message, contact)
      app = @package.app

      return unless channel_id

      profile_data = {
        name: channel_id
      }

      if contact["displayName"]
        profile_data.merge!({
                              name: contact["displayName"]
                            })
      end

      data = {
        properties: profile_data
      }

      external_profile = app.external_profiles.find_by(
        provider: PROVIDER,
        profile_id: channel_id
      )

      participant = external_profile&.app_user

      ## todo: check user for this & previous conversation
      ## via twitter with the twitter user id
      if participant.blank?
        participant = app.add_anonymous_user(data)
        participant.external_profiles.create(
          provider: PROVIDER,
          profile_id: channel_id
        )
      end

      participant
    end
  end
end
