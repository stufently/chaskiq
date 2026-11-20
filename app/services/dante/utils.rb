# frozen_string_literal: true

class Dante::Utils
  def self.extract_plain_text(nodes)
    nodes.each_with_object(+"") do |node, text|
      case node["type"]
      when "text"
        text << "#{node['text']} "
      else
        node_content = node["content"]
        text << extract_plain_text(node_content) if node_content
      end
    end.strip
  end

  def self.get_blocks(serialized_content)
    JSON.parse(serialized_content)["content"]
  end
end
