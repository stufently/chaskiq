# frozen_string_literal: true

# This Ruby code provides a Renderer class that can be used to convert ProseMirror JSON into HTML.
# The implementation closely follows the original JavaScript code,

module Dante
  class Renderer
    CONTAINER_ELEMENTS = {
      "blockquote" => ["blockquote", nil],
      "paragraph" => ["p", "graf graf--p"],
      "bulletList" => ["ul", "graf graf--ul"],
      "listItem" => ["li", "graf graf--li"],
      "codeBlock" => ["pre", "graf graf--pre"]
    }.freeze
    private_constant :CONTAINER_ELEMENTS

    attr_accessor :raw, :html, :theme, :domain

    def initialize(raw:, html: nil, theme: nil, domain: Chaskiq::Config.get("HOST"))
      @raw = raw
      @html = html
      @theme = theme
      @domain = domain
    end

    def convert_node_to_element(node)
      type = node[:type]
      if (container = CONTAINER_ELEMENTS[type])
        tag, style = container
        create_element(tag, style, traverse_nodes(node[:content]))
      elsif type == "heading"
        render_heading(node)
      elsif type == "text"
        handle_text_node(node)
      elsif (renderer = media_renderer(type))
        render_media(node, *renderer)
      else
        Rails.logger.debug { "no handler for node #{node}" }
        nil
      end
    end

    def handle_text_node(node)
      text_element = node[:text]

      if node[:marks].present?
        node[:marks].reduce(text_element) { |element, mark| handle_mark(element, mark, node) }
      else
        text_element
      end
    end

    def create_element(tag, klass, content, **attrs)
      attrs_string = attrs.map { |key, value| "#{key}=\"#{value}\"" }.join
      class_string = klass ? " class=\"#{klass}\" " : ""
      content_string = Array(content).join
      "<#{tag}#{class_string} #{attrs_string}>#{content_string}</#{tag}>"
    end

    def handle_mark(element, mark, _node)
      case mark[:type]
      when "textStyle"
        color = mark[:attrs][:color].is_a?(Hash) && mark[:attrs][:color].key?(:color) ? mark[:attrs][:color][:color] : mark[:attrs][:color]
        create_element("span", nil, element, style: "color: #{color};")
      when "bold"
        create_element("strong", nil, element)
      when "italic"
        create_element("em", nil, element)
      when "code"
        create_element("code", "graf code", element)
      when "link"
        create_element("a", "graf markup--anchor markup--anchor-readOnly", element,
                       href: mark[:attrs][:href], target: mark[:attrs][:target], rel: "noopener noreferrer nofollow")
      else
        Rails.logger.debug { "no handler for mark #{mark}" }
        element
      end
    end

    def traverse_nodes(nodes)
      return nil unless nodes

      nodes.map { |node| convert_node_to_element(node) }
    end

    def render
      traverse_nodes(raw[:content]).join(" ")
    end

    private

    def render_heading(node)
      level = begin
        node[:attrs][:level]
      rescue StandardError
        2
      end
      create_element("h#{level}", "graf graf--h", traverse_nodes(node[:content]))
    end

    def media_renderer(type)
      case type
      when "ImageBlock" then [Dante::ImageBlockRenderer, true]
      when "FileBlock" then [Dante::FileBlockRenderer, true]
      when "VideoBlock" then [Dante::VideoBlockRenderer, false]
      when "DividerBlock" then [Dante::DividerBlockRenderer, true]
      when "AudioRecorderBlock" then [Dante::AudioRecorderRenderer, true]
      when "EmbedBlock" then [Dante::EmbedBlockRenderer, false]
      end
    end

    def render_media(node, renderer_class, pass_domain)
      options = { block_key: node[:id], data: node[:attrs] }
      options[:domain] = domain if pass_domain
      renderer_class.new(**options).render
    end
  end
end
