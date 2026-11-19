require "action_view"
require "uri"

class MessageApis::BlockManager
  include ActionView::Helpers::SanitizeHelper

  MEDIA_BLOCK_TYPES = %w[ImageBlock FileBlock AudioRecorderBlock VideoBlock].freeze
  private_constant :MEDIA_BLOCK_TYPES

  def self.get_blocks(serialized_content)
    document = JSON.parse(serialized_content)
    return unless document.is_a?(Hash)
    return document["content"] if document["content"].is_a?(Array)
    return unless document["blocks"].is_a?(Array)

    document["blocks"].grep(Hash).map do |block|
      if %w[key inlineStyleRanges entityRanges].any? { |key| block.key?(key) }
        draft_block(block)
      else
        block
      end
    end
  end

  def self.plain_text(blocks)
    nodes = blocks.grep(Hash)
    text = nodes.map { |node| node_text(node).strip }.reject(&:empty?).join("\n")
    return text unless text.empty?

    nodes.flat_map { |node| media_captions(node) }.join("\n")
  end

  def self.media_blocks(blocks)
    return [] unless blocks.is_a?(Array)

    blocks.grep(Hash).select { |block| MEDIA_BLOCK_TYPES.include?(block["type"]) }
  end

  def self.deliver_attachments(attachments, plain_text, send_text:, captionless: [], **hooks)
    hooks.assert_valid_keys(:on_success, :on_failure, :already_sent)
    already_sent = hooks.fetch(:already_sent, 0)
    remaining, delivered_indices = already_sent.is_a?(Integer) ? [already_sent, []] : [0, already_sent]
    on_success = delivery_success_hook(hooks[:on_success], already_sent)
    on_failure = hooks[:on_failure]
    failures = []
    first_success = nil
    last_response = nil
    media_delivered = false
    caption = plain_text.presence
    omit_caption = captionless.respond_to?(:call) ? captionless : ->(type, _url) { captionless.include?(type) }
    caption = nil if caption && caption_delivered?(attachments, delivered_indices, omit_caption)

    attachments.each_with_index do |media, index|
      url = delivery_url(media)
      next unless url

      type = media["type"]
      media_caption = omit_caption.call(type, url) ? nil : caption
      if delivered_indices.include?(index) || remaining.positive?
        remaining -= 1 if remaining.positive?
      else
        last_response = yield(type, url, media_caption)
        unless last_response.success?
          failures << last_response
          next
        end

        on_success&.call(last_response, index)
        first_success ||= last_response
      end
      media_delivered = true
      caption = nil if media_caption
    end

    text = media_delivered ? caption : plain_text.presence
    text_index = attachments.size
    text_response = send_text.call(text) if text && remaining.zero? && delivered_indices.exclude?(text_index)
    if text_response.respond_to?(:success?)
      if text_response.success?
        on_success&.call(text_response, text_index)
        successful_text = text_response
      else
        failures << text_response
      end
    end

    result = if media_delivered
               first_success || successful_text
             elsif text
               text_response
             else
               last_response
             end
    result
  ensure
    report_failures(on_failure, failures, result) if on_failure
  end

  def self.delivery_success_hook(callback, already_sent)
    return unless callback
    return callback unless already_sent.is_a?(Integer)

    ->(response, _index) { callback.call(response) }
  end

  def self.caption_delivered?(attachments, delivered_indices, omit_caption)
    return true if delivered_indices.include?(attachments.size)

    delivered_indices.any? do |index|
      media = attachments[index]
      url = delivery_url(media)
      url && !omit_caption.call(media["type"], url)
    end
  end

  def self.delivery_url(media)
    attrs = block_data(media) if media
    absolute_url(attrs["url"]) if attrs.is_a?(Hash)
  end

  def self.report_failures(callback, failures, result)
    failures.each do |failure|
      next if failure.equal?(result)

      begin
        callback.call(failure)
      rescue StandardError => e
        Rails.logger.error("Attachment failure hook raised #{e.class}")
      end
    end
  end

  def self.absolute_url(url)
    return unless url.is_a?(String) && url.present?

    if url.start_with?("//")
      url = "https:#{url}"
    elsif !url.match?(/\A[A-Za-z][A-Za-z0-9+.-]*:/)
      host = Chaskiq::Config.get("HOST").to_s.sub(%r{/+\z}, "")
      url = "#{host}/#{url.sub(%r{\A/+}, '')}"
    end

    address = url.match(%r{\A([Hh][Tt][Tt][Pp][Ss]?://[^/?#]*)(.*)\z}m)
    return unless address

    authority, suffix = address.captures
    path_and_query, separator, fragment = suffix.partition("#")
    unsafe = /%(?![A-Fa-f0-9]{2})|[^A-Za-z0-9._~!$&'()*+,;=:@\/?%\-]/
    encoded = authority + URI::DEFAULT_PARSER.escape(path_and_query, unsafe) +
              separator + URI::DEFAULT_PARSER.escape(fragment, unsafe)
    encoded if URI.parse(encoded).host.present?
  rescue URI::Error, ArgumentError, EncodingError
    nil
  end

  # draft to pm
  def self.block_mapping(type)
    {
      "file" => "FileBlock",
      "recorded-audio" => "AudioRecorderBlock",
      "recorded-video" => "VideoBlock",
      "video" => "VideoBlock",
      "image" => "ImageBlock",
      "unstyled" => "text",
      "divider" => "DividerBlock",
      "header-one" => "heading",
      "header-two" => "heading",
      "header-three" => "heading",
      "header-four" => "heading"
    }[type]
  end

  def self.block_data(block)
    # block["data"]
    block["attrs"]
  end

  def self.serialized_text(text)
    {
      type: "doc",
      content: [{ type: "text", text: text.to_s }]
    }.to_json

    # key = ("a".."z").to_a.sample(8).join

    # {
    #  "blocks" => [
    #    { "key" => key, "text" => text.to_s, "type" => "unstyled", "depth" => 0, "inlineStyleRanges" => [], "entityRanges" => [], "data" => {} }
    #  ],
    #  "entityMap" => {}
    # }
  end

  def self.draft_block(block)
    type = block_mapping(block["type"])
    text = block["text"].to_s
    media = MEDIA_BLOCK_TYPES.include?(type)
    if media || type == "DividerBlock"
      attrs = block["data"]
      if media && text.present?
        attrs = (attrs.is_a?(Hash) ? attrs : {}).merge("caption" => text)
      end
      return { "type" => type, "attrs" => attrs }
    end

    children = text.empty? ? [] : [{ "type" => "text", "text" => text }]
    { "type" => "paragraph", "content" => children }
  end

  def self.node_text(node)
    case node["type"]
    when "text"
      node["text"].to_s
    when "hardBreak", "hard_break"
      "\n"
    else
      children = Array(node["content"]).grep(Hash)
      children.chunk { |child| %w[text hardBreak hard_break].include?(child["type"]) }
              .flat_map do |inline, group|
        texts = group.map { |child| node_text(child) }
        inline ? [texts.join.strip] : texts.map(&:strip)
      end.reject(&:empty?).join("\n")
    end
  end

  def self.media_captions(node)
    if MEDIA_BLOCK_TYPES.include?(node["type"])
      attrs = block_data(node)
      caption = attrs["caption"] if attrs.is_a?(Hash)
      return [caption.strip] if caption.is_a?(String) && caption.present?
    end

    Array(node["content"]).grep(Hash).flat_map { |child| media_captions(child) }
  end

  private_class_method :draft_block, :node_text, :media_captions,
                       :delivery_success_hook, :caption_delivered?, :delivery_url, :report_failures
end
