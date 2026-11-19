require "action_view"
require "uri"

class MessageApis::BlockManager
  include ActionView::Helpers::SanitizeHelper

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
    blocks.grep(Hash).map { |block| node_text(block).strip }.reject(&:empty?).join("\n")
  end

  def self.absolute_url(url)
    return unless url.is_a?(String) && url.present?

    unless url.match?(%r{\Ahttps?://}i)
      return if url.match?(/\A[a-z][a-z\d+.-]*:/i)

      host = Chaskiq::Config.get("HOST").to_s.sub(%r{/+\z}, "")
      url = "#{host}/#{url.sub(%r{\A/+}, '')}"
    end

    address = url.match(%r{\A(https?://[^/?\#]*)(.*)\z}im)
    return unless address

    authority, suffix = address.captures
    path_and_query, separator, fragment = suffix.partition("#")
    unsafe = /%(?![a-f0-9]{2})|[^a-z0-9._~!$&'()*+,;=:@\/?%\-]/i
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
    type = block["type"]
    case type
    when "image", "file", "recorded-audio", "recorded-video", "video", "divider"
      { "type" => block_mapping(type), "attrs" => block["data"] }
    else
      text = block["text"].to_s
      children = text.empty? ? [] : [{ "type" => "text", "text" => text }]
      { "type" => "paragraph", "content" => children }
    end
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

  private_class_method :draft_block, :node_text
end
