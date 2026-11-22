# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dante::Renderer, "#convert_node_to_element" do
  let(:renderer) { described_class.new(raw: {}, domain: "https://chat.example.com") }
  let(:content) { [{ type: "text", text: "Hello" }] }

  {
    "blockquote" => "<blockquote >Hello</blockquote>",
    "paragraph" => '<p class="graf graf--p"  >Hello</p>',
    "bulletList" => '<ul class="graf graf--ul"  >Hello</ul>',
    "listItem" => '<li class="graf graf--li"  >Hello</li>',
    "codeBlock" => '<pre class="graf graf--pre"  >Hello</pre>'
  }.each do |type, html|
    it "renders the exact #{type} HTML" do
      expect(renderer.convert_node_to_element(type: type, content: content)).to eq(html)
    end
  end

  it "preserves an explicitly supplied heading level" do
    node = { type: "heading", attrs: { level: 3 }, content: content }
    expect(renderer.convert_node_to_element(node)).to eq('<h3 class="graf graf--h"  >Hello</h3>')
  end

  it "defaults to level two when the heading attributes are missing" do
    node = { type: "heading", content: content }
    expect(renderer.convert_node_to_element(node)).to eq('<h2 class="graf graf--h"  >Hello</h2>')
  end

  it "preserves the empty level when the attributes exist but provide no level" do
    node = { type: "heading", attrs: {}, content: content }
    expect(renderer.convert_node_to_element(node)).to eq('<h class="graf graf--h"  >Hello</h>')
  end

  it "renders nested marks in the input order" do
    node = { type: "text", text: "Hello", marks: [{ type: "bold" }, { type: "italic" }] }
    expect(renderer.convert_node_to_element(node)).to eq("<em ><strong >Hello</strong></em>")
  end

  it "omits an unknown node type" do
    expect(renderer.convert_node_to_element(type: "unknown")).to be_nil
  end

  {
    "ImageBlock" => [Dante::ImageBlockRenderer, true],
    "FileBlock" => [Dante::FileBlockRenderer, true],
    "VideoBlock" => [Dante::VideoBlockRenderer, false],
    "DividerBlock" => [Dante::DividerBlockRenderer, true],
    "AudioRecorderBlock" => [Dante::AudioRecorderRenderer, true],
    "EmbedBlock" => [Dante::EmbedBlockRenderer, false]
  }.each do |type, (renderer_class, pass_domain)|
    it "renders #{type} with the original constructor arguments" do
      attrs = { url: "https://cdn.example.com/resource" }
      options = { block_key: "node-key", data: attrs }
      options[:domain] = "https://chat.example.com" if pass_domain
      block = double("media renderer", render: "<media>#{type}</media>")
      expect(renderer_class).to receive(:new).with(**options).and_return(block)

      expect(renderer.convert_node_to_element(type: type, id: "node-key", attrs: attrs))
        .to eq("<media>#{type}</media>")
    end
  end
end
