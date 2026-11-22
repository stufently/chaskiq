# frozen_string_literal: true

require "json"

module Dante
  class Converter
    def self.draftjs_to_prosemirror(draftjs_content)
      content_state = JSON.parse(draftjs_content, symbolize_names: true)
      blocks = content_state[:blocks]
      entity_map = content_state[:entityMap]

      prosemirror_nodes = blocks.map do |block|
        convert_block_to_prosemirror_node(block, entity_map)
      end

      { type: "doc", content: prosemirror_nodes }
    end

    def self.convert_block_to_prosemirror_node(block, entity_map)
      node = {
        type: convert_block_type(block[:type]),
        content: convert_inline_styles(block, entity_map)
      }

      if node[:type] == "heading"
        a = { "one" => 1, "two" => 2, "three" => 3 }
        node[:attrs] = { level: a[block[:type].split("-").last] || 0 }
      end

      if %w[DividerBlock ImageBlock EmbedBlock VideoBlock VideoRecorderBlock AudioRecorderBlock].include?(node[:type])
        node[:attrs] = block[:data]
      end

      node
    end

    def self.convert_inline_styles(block, entity_map)
      text = block[:text]
      inline_style_ranges = block[:inlineStyleRanges]
      entity_ranges = block[:entityRanges]

      nodes = []
      position = 0

      while position < text.length
        style = ranges_at(inline_style_ranges, position)
        marks = style.flat_map { |s| convert_style_to_marks(s[:style]) }
        marks.concat(link_marks(entity_ranges, entity_map, position))

        next_position = next_range_end(style + entity_ranges, position) || text.length
        nodes << {
          type: "text",
          text: text[position...next_position],
          marks: marks
        }
        position = next_position
      end

      nodes
    end

    # The ranges ({offset:, length:}) that cover the character at position.
    def self.ranges_at(ranges, position)
      ranges.select { |range| position >= range[:offset] && position < (range[:offset] + range[:length]) }
    end

    # The link mark of the first entity range covering position, if its entity is a LINK.
    def self.link_marks(entity_ranges, entity_map, position)
      entity_range = entity_ranges.find { |range| position >= range[:offset] && position < (range[:offset] + range[:length]) }
      return [] unless entity_range

      entity = entity_map[entity_range[:key].to_s.to_sym]
      entity[:type] == "LINK" ? [{ type: "link", attrs: { href: entity[:data][:url] } }] : []
    end

    # The nearest end of the given ranges after position (nil when none ends after it).
    def self.next_range_end(ranges, position)
      ranges.map { |range| range[:offset] + range[:length] }.select { |pos| pos > position }.min
    end

    def self.convert_block_type(draftjs_block_type)
      case draftjs_block_type
      when "header-one", "header-two", "header-three", "header-four", "header-five", "header-six"
        "heading"
      when "unordered-list-item"
        "listItem"
      when "code-block"
        "codeBlock"
      when "blockquote"
        "blockquote"
      when "image"
        "ImageBlock"
      when "video"
        "VideoBlock"
      when "embed"
        "EmbedBlock"
      when "divider"
        "DividerBlock"
      when "video-recorder"
        "VideoRecorderBlock"
      when "audio-recorder"
        "AudioRecorderBlock"
      else
        "paragraph"
      end
    end

    def self.convert_style_to_marks(style)
      marks = []

      marks << { type: "bold" } if style.include?("BOLD")
      marks << { type: "italic" } if style.include?("ITALIC")
      marks << { type: "code" } if style.include?("CODE")
      if style.include?("CUSTOM_COLOR")
        marks << { type: "textStyle", attrs: { color: style.match(/CUSTOM_COLOR_(#[0-9a-fA-F]{6})/)&.captures&.first } }
      end

      marks
    end
  end
end
