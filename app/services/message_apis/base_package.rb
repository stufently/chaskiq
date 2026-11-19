module MessageApis
  class BasePackage
    def initialize(config:)
      @config = config
    end

    def trigger(event); end

    def process_event(params, package); end

    def enqueue_process_event(params, package)
      HookMessageReceiverJob.perform_later(
        id: package.id,
        params: params.permit!.to_h
      )
      { status: :ok }
    end

    # triggered when a new chaskiq message is created
    # will triggered just after the ws notification
    def notify_message(conversation:, part:, channel:)
      return if sent_request_count(part).positive? && !resumable_delivery?(part)

      response = send_message(conversation, part)
      store_message_id(part, response) unless response.nil?
    end

    private

    def sent_request_count(part)
      return 0 unless part.persisted?

      part.conversation_part_channel_sources.where(provider: self.class::PROVIDER).count
    end

    def resumable_delivery?(part)
      plugin = self.class
      return false unless plugin.const_defined?(:RESUMABLE_DELIVERY, false) && plugin::RESUMABLE_DELIVERY == true

      blocks = BlockManager.get_blocks(part.message.as_json["serialized_content"])
      BlockManager.media_blocks(blocks).any?
    rescue JSON::ParserError, ArgumentError, TypeError, NoMethodError, EncodingError
      false
    end

    def delivery_hooks(conversation, part)
      {
        already_sent: sent_request_count(part),
        on_success: ->(response) { store_message_id(part, response) if part.persisted? },
        on_failure: ->(response) { report_delivery_failure(conversation, part, response) }
      }
    end

    def message_id_for(response)
      get_message_id(response_json(response)).to_s.presence
    rescue TypeError, NoMethodError, KeyError
      nil
    end

    def store_message_id(part, response)
      return if response.respond_to?(:success?) && !response.success?

      message_id = message_id_for(response)
      return unless message_id

      part.conversation_part_channel_sources.find_or_create_by(
        provider: self.class::PROVIDER,
        message_source_id: message_id
      )
    end

    def response_json(response)
      JSON.parse(response.respond_to?(:body) ? response.body : response)
    rescue JSON::ParserError, TypeError
      nil
    end

    def report_delivery_failure(conversation, part, response)
      body, error = error_response_fields(response)
      code = body["code"] || body["error_code"] || error["code"]
      texts = body.values_at("message", "description", "title") + error.values_at("title", "description")
      text = texts.find { |value| value.is_a?(String) && value.present? }
      status = response.status if response.respond_to?(:status)
      add_error_event(conversation, "bypass-internal-#{part.id}", status: status, code: code, text: text)
    end

    def error_response_fields(response)
      body = response_json(response)
      body = {} unless body.is_a?(Hash)
      error = body["errors"].first if body["errors"].is_a?(Array)
      error = {} unless error.is_a?(Hash)
      [body, error]
    end

    def add_error_event(conversation, source_id, status:, code:, text:)
      text = text.to_s.gsub(%r{[A-Za-z][A-Za-z0-9+.-]*://[^[:space:]]+}, "[url]").squish.truncate(200)
      code = nil unless code.is_a?(Integer) || (code.is_a?(String) && code.match?(/\A[\w.-]{1,32}\z/))

      conversation.add_message_event(
        action: "errored: #{text}",
        provider: self.class::PROVIDER,
        message_source_id: source_id,
        data: { status: status, code: code, message: text }
      )
    end
  end
end
