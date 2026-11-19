# frozen_string_literal: true

require "rack/mime"

module MessageApis::TelnyxSms
  class Api < MessageApis::BasePackage

    def self.definition_info
      {
        name: "TelnyxSms",
        description: "Interfaces Telnyx SMS",
        icon: "https://logo.clearbit.com/telnyx.com",
        state: "enabled",
        definitions: [
          {
            name: "api_key",
            type: "string",
            required: true,
            grid: { xs: "w-full", sm: "w-full" }
          },
          {
            name: "profile_id",
            type: "string",
            required: true,
            grid: { xs: "w-full", sm: "w-full" }
          },
          {
            name: "phones",
            label: "Numbers pool",
            hint: "Desired format ie: +17777777777, add comma separated values for your phones, ie:. phone1,phone2,phone3",
            type: "textarea",
            required: true,
            grid: { xs: "w-full", sm: "w-full" }
          }

        ]
      }
    end

    include MessageApis::Helpers

    attr_accessor :url, :api_key, :conn

    # URL = "https://api.telnyx.com/v2/messaging"
    URL = "https://api.telnyx.com/v2/messages"
    PROVIDER = "TelnyxSms"
    RESUMABLE_DELIVERY = true
    MMS_TYPES = {
      ".jpg" => "image/jpeg",
      ".jpeg" => "image/jpeg",
      ".png" => "image/png",
      ".gif" => "image/gif",
      ".mp4" => "video/mp4",
      ".3gp" => "video/3gpp",
      ".txt" => "text/plain",
      ".vcf" => "text/vcard",
      ".vcard" => "text/vcard"
    }.freeze
    MAX_MEDIA_BYTES = 5 * 1024 * 1024
    private_constant :MMS_TYPES, :MAX_MEDIA_BYTES

    def initialize(config:)
      @package = config[:package]
      @api_key = config[:api_key]
      @profile_id = config[:profile_id]

      @conn = Faraday.new(
        request: {
          params_encoder: Faraday::FlatParamsEncoder
        }
      )

      @conn.headers = {
        "Content-Type" => "application/json",
        "Authorization" => "Bearer #{@api_key}",
        "Accept" => "application/json"
      }

      self
    end

    def validate_integration
      # @package.settings[:phones].split(",").each do ||
    end

    def integration_data_prepare(object)
      formatted_phones = object.settings[:phones].delete(" ").split(",").map do |d|
        "+#{d.gsub(/\D/, '')}"
      end.join(",")

      object.settings[:phones] = formatted_phones
    end

    def register_webhook(app_package, integration); end

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
      process_message(params, @package)
    end

    def send_message(conversation, part)
      return if part.private_note?

      blocks = outbound_blocks(part)
      return if blocks.blank?

      channel_id = conversation.conversation_channels.find_by(provider: PROVIDER)&.provider_channel_id
      return if channel_id.blank?

      response = deliver_message(conversation, part, channel_id, blocks)
      return response if response.nil? || response.success?

      report_delivery_failure(conversation, part, response)
      nil
    end

    def outbound_blocks(part)
      message = part.message.as_json
      content = message["serialized_content"]
      if content.blank?
        text = Loofah.fragment(message["html_content"].to_s).to_text(encode_special_chars: false).strip
        return if text.blank?

        content = MessageApis::BlockManager.serialized_text(text)
      end

      MessageApis::BlockManager.get_blocks(content)
    rescue JSON::ParserError, TypeError, NoMethodError
      nil
    end

    def deliver_message(conversation, part, channel_id, blocks)
      text = MessageApis::BlockManager.plain_text(blocks)
      media = MessageApis::BlockManager.media_blocks(blocks)
      return if media.empty? && text.blank?

      sender = resolve_outbound_phone(channel_id)
      send_sms = ->(body, urls = []) { send_sms_message(channel_id, body, urls) { sender } }
      return send_sms.call(text) if media.empty?

      attachments, links = media.partition { |block| supported_media?(block) }
      text = [text.presence, *links.filter_map { |block| attachment_url(block) }].compact.join("\n")
      MessageApis::BlockManager.deliver_attachments(
        attachments, text,
        send_text: send_sms,
        **delivery_hooks(conversation, part)
      ) do |_type, url, caption|
        send_sms.call(caption, [url])
      end
    end

    def attachment_url(block)
      attrs = MessageApis::BlockManager.block_data(block)
      MessageApis::BlockManager.absolute_url(attrs["url"]) if attrs.is_a?(Hash)
    end

    def supported_media?(block)
      url = attachment_url(block)
      url && MMS_TYPES.key?(File.extname(URI.parse(url).path.to_s).downcase)
    end

    private :outbound_blocks, :deliver_message, :attachment_url, :supported_media?

    def get_message_id(response_data)
      response_data.dig("data", "id")
    end

    def process_message(params, package)
      data = params[:data]

      case data[:event_type]
      when "message.received"
        process_incoming_message(data)
      when "message.finalized"
        process_status(data[:payload])
      end
    end

    def process_incoming_message(data)
      payload = data[:payload]
      channel_id = payload[:from][:phone_number]
      message_id = payload[:id]
      app = @package.app

      conversation = find_conversation_by_channel(PROVIDER, channel_id.to_s)

      return if conversation && conversation.conversation_part_channel_sources
                                            .find_by(message_source_id: message_id.to_s).present?

      text = payload["text"].to_s
      blocks = inbound_blocks(text, payload["media"], message_id)
      return if blocks.empty?

      user_data = {
        "id" => channel_id,
        "first_name" => "telnyx:#{channel_id}"
      }

      participant = add_participant(user_data, PROVIDER)

      if conversation.blank?
        conversation = app.conversations.create(
          main_participant: participant,
          conversation_channels_attributes: [
            provider: PROVIDER,
            provider_channel_id: channel_id
          ]
        )
      end

      conversation.add_message(
        from: participant,
        message: {
          html_content: text,
          serialized_content: main_doc(blocks).to_json
        },
        provider: PROVIDER,
        message_source_id: message_id,
        check_assignment_rules: true
      )

      conversation.close! if should_stop_conversation?(text)
    end

    def inbound_blocks(text, media, message_id)
      blocks = text.split("\n").reject(&:empty?).map { |line| serialized_block(line) }
      Array(media).grep(Hash).each_with_index { |item, index| blocks << media_block(item, message_id, index) }
      blocks
    end

    def media_block(media, message_id, index)
      content_type = media["content_type"].to_s.partition(";").first.strip.downcase.presence
      body = download_media(media["url"])
      return unavailable_attachment(content_type) unless body

      content_type ||= body.mime_type || "application/octet-stream"
      extension = MMS_TYPES.key(content_type) || Rack::Mime::MIME_TYPES.key(content_type)
      upload = direct_upload(file: body, filename: "#{message_id}-#{index}#{extension}", content_type: content_type)
      if content_type.start_with?("image/")
        photo_block(url: upload[:url], text: "")
      else
        file_block(url: upload[:url], text: content_type)
      end
    rescue StandardError => e
      Rails.logger.warn("Telnyx MMS attachment failed (#{e.class})")
      unavailable_attachment(content_type)
    end

    def unavailable_attachment(content_type)
      serialized_block("[attachment unavailable: #{content_type || 'application/octet-stream'}]")
    end

    def download_media(url)
      unless media_url?(url)
        Rails.logger.warn("Telnyx MMS attachment URL rejected")
        return
      end

      MessageApis::SafeDownload.fetch(url, max_bytes: MAX_MEDIA_BYTES, allow_own_host: false,
                                           headers: { "Authorization" => "Bearer #{@api_key}" },
                                           url_allowed: ->(uri) { media_url?(uri.to_s) })
    end

    def media_url?(url)
      uri = URI.parse(url.to_s)
      host = uri.host.to_s.downcase
      uri.is_a?(URI::HTTPS) && uri.userinfo.nil? && (host == "telnyx.com" || host.end_with?(".telnyx.com"))
    rescue URI::Error
      false
    end

    def app_channel(id)
      return if id.blank?

      ConversationPartChannelSource.joins(conversation_part: :conversation)
                                   .find_by(provider: PROVIDER, message_source_id: id,
                                            conversations: { app_id: @package.app_id })
    end

    def process_status(payload)
      id = payload[:id]
      part = app_channel(id)&.conversation_part
      return unless part

      statuses = Array(payload[:to]).pluck(:status)
      part.read! if statuses.include?("delivered")
      return unless statuses.intersect?(%w[sending_failed delivery_failed])

      error = Array(payload[:errors]).first || {}
      text = error[:title].presence || error[:detail].presence || statuses.join(", ")
      add_error_event(part.conversation, "telnyx-failed-#{id}", status: nil, code: error[:code], text: text)
    end

    private :inbound_blocks, :media_block, :unavailable_attachment,
            :download_media, :media_url?, :app_channel, :process_status

    def send_sms_message(channel_id, message, media_urls = [])
      channel_id = channel_id.delete("+")
      data = { to: "+#{channel_id}" }
      data[:text] = message if message.present?
      data[:media_urls] = media_urls if media_urls.present?

      sender = block_given? ? yield : resolve_outbound_phone(channel_id)
      @conn.post(URL, data.merge(sender).to_json)
    end

    def should_stop_conversation?(text)
      text == "STOP"
    end

    def resolve_outbound_phone(phone)
      phone = phone.delete("+")
      key = phones_data.keys.find { |o| phone.starts_with?(o) }
      case key
      when nil
        { messaging_profile_id: @profile_id }
      else
        { from: phones_data[key]&.sample }
      end
    end

    def phones_data
      @phones_data ||= get_phones_data
    end

    def get_phones_data
      data = {}
      phones = @package.settings["phones"] || ""
      phones.split(",").each do |o|
        pn = Phonelib.parse(o)
        code = pn.country_code
        data[code].present? ? data[code] << o : data[code] = [o]
      end
      @phones_data = data
    end
  end
end
