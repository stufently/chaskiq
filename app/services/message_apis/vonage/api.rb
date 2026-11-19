# frozen_string_literal: true

module MessageApis::Vonage
  class Api < MessageApis::BasePackage

    def self.definition_info
      {
        name: "Vonage",
        tag_list: ["conversations.added"],
        description: "Interfaces Vonage Whatsapp",
        icon: "https://logo.clearbit.com/vonage.com",
        state: Rails.env.production? ? "disabled" : "enabled",
        definitions: [
          {
            name: "user_id",
            label: "Phone",
            type: "string",
            required: true,
            hint: "The Vonage Whatsapp number (format: 14155231223)",
            grid: { xs: "w-full", sm: "w-full" }
          },
          {
            name: "api_key",
            label: "Your Vonage API key",
            type: "string",
            required: true,
            grid: { xs: "w-full", sm: "w-full" }
          },
          {
            name: "api_secret",
            label: "Your Vonage API secret",
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

    include MessageApis::Helpers
    PROVIDER = "vonage"
    RESUMABLE_DELIVERY = true

    attr_accessor :url, :api_token, :api_key, :conn

    def initialize(config:)
      @api_key = config["api_key"]
      @api_token = config["api_secret"]
      @phone = config["user_id"]

      @url = if config["sandbox"]
               "https://messages-sandbox.nexmo.com/v0.1/messages"
             else
               "https://api.nexmo.com/v0.1/messages"
             end

      @conn = Faraday.new(
        request: {
          params_encoder: Faraday::FlatParamsEncoder
        }
      )

      @conn.headers = {
        "X-TOKEN" => @api_token,
        "Content-Type" => "application/json",
        "Accept" => "application/json"
      }

      @conn.request(:authorization, :basic, @api_key, @api_token)

      self
    end

    def trigger(event); end

    def process_event(params, package)
      @package = package
      current = params["current"]

      if params["status"].present?
        case params["status"]
        when "read"
          process_read(params["message_uuid"])
          return
        end
      end

      process_message(params, @package)
    end

    def get_message_id(response_data)
      response_data["message_uuid"]
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
        from: { type: "whatsapp", number: @phone },
        to: { type: "whatsapp", number: profile_id }
      }
      post_content = ->(data) { @conn.post(@url, addressing.merge(message: { content: data }).to_json) }
      send_text = ->(text) { post_content.call(type: "text", text: text) }
      attachments = MessageApis::BlockManager.media_blocks(blocks)
      MessageApis::BlockManager.deliver_attachments(
        attachments, plain_message, send_text: send_text, **delivery_hooks(conversation, part)
      ) do |block_type, url, caption|
        type = media_types.fetch(block_type)
        data = { url: url }
        data[:caption] = caption if caption
        post_content.call(type: type, type => data)
      end
    end

    def process_message(params, package)
      @package = package

      app = package.app

      message_id = params["message_uuid"]

      channel_id, vonage_user, agent_sender = get_channel_data(params)

      conversation = find_conversation_by_channel(channel_id)

      return if conversation && conversation.conversation_part_channel_sources
                                            .find_by(message_source_id: message_id).present?

      text = params.dig("message", "content", "text")

      serialized_content = serialize_content(params)

      participant = add_participant(vonage_user)

      add_message(
        conversation: conversation,
        participant: participant,
        channel_id: channel_id,
        from: agent_sender ? @package.app.agents.first : participant,
        serialized_content: serialized_content,
        text: text,
        message_id: message_id
      )
    end

    def get_channel_data(params)
      sender_id = params["from"]["number"]
      target_id = params["to"]["number"]
      # determine the id of the user (channel)
      cond = sender_id == @package.user_id.to_s
      channel_id = cond ? target_id : sender_id
      vonage_user = cond ? target_id : sender_id
      agent_sender = cond
      [channel_id, vonage_user, agent_sender]
    end

    def add_message(
      conversation:,
      participant:,
      channel_id:,
      from:,
      serialized_content:,
      text:,
      message_id:
    )
      if conversation.blank?
        conversation = @package.app.conversations.create(
          main_participant: participant,
          conversation_channels_attributes: [
            provider: PROVIDER,
            provider_channel_id: channel_id
          ]
        )
      end

      # TODO: serialize message
      conversation.add_message(
        from: from, # agent_required ? Agent.first : participant,
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
      text = data.dig("message", "content", "text")
      if data.dig("message", "content", "type") == "text"
        text_block(text) if text.present?
      else
        attachment_block(data)
      end
    end

    def attachment_block(data)
      image_data = data.dig("message", "content")
      {
        blocks: [media_block(image_data)].compact,
        entityMap: {}
      }.to_json
    end

    def media_block(data)
      media_type = data["type"]
      media = case media_type
              when "unsupported" then nil
              when "image"
                url = data["image"]["url"]
                text = data["image"]["caption"]
                photo_block(url: url, text: text)
              when "video"
                url = data["video"]["url"]
                text = data["video"]["caption"]
                gif_block(url: url, text: text)
              when "audio", "file"
                url = data[media_type]["url"]
                text = data[media_type]["caption"]
                file_block(url: url, text: text)
              end
    end

    def add_participant(vonage_user)
      app = @package.app
      if vonage_user

        data = {
          properties: {
            name: vonage_user
          }
        }

        external_profile = app.external_profiles.find_by(
          provider: PROVIDER,
          profile_id: vonage_user
        )

        participant = external_profile&.app_user

        ## todo: check user for this & previous conversation
        ## via twitter with the twitter user id
        if participant.blank?
          participant = app.add_anonymous_user(data)
          participant.external_profiles.create(
            provider: PROVIDER,
            profile_id: vonage_user
          )
        end

        participant
      end
    end
  end
end
