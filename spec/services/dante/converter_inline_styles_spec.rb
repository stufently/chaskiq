# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dante::Converter, ".convert_inline_styles" do
  def convert(text:, inline_style_ranges: [], entity_ranges: [], entity_map: {})
    described_class.convert_inline_styles(
      { text: text, inlineStyleRanges: inline_style_ranges, entityRanges: entity_ranges },
      entity_map
    )
  end

  it "returns a single unmarked node when there are no ranges" do
    expect(convert(text: "hello")).to eq([{ type: "text", text: "hello", marks: [] }])
  end

  it "returns empty array for empty text" do
    expect(convert(text: "")).to eq([])
  end

  it "splits BOLD [0,4) in 'bold text' into two nodes" do
    result = convert(
      text: "bold text",
      inline_style_ranges: [{ style: "BOLD", offset: 0, length: 4 }]
    )
    expect(result).to eq([
                           { type: "text", text: "bold", marks: [{ type: "bold" }] },
                           { type: "text", text: " text", marks: [] }
                         ])
  end

  it "handles overlapping BOLD [0,3) + ITALIC [0,6) in 'abcdefghi'" do
    result = convert(
      text: "abcdefghi",
      inline_style_ranges: [
        { style: "BOLD", offset: 0, length: 3 },
        { style: "ITALIC", offset: 0, length: 6 }
      ]
    )
    expect(result).to eq([
                           { type: "text", text: "abc", marks: [{ type: "bold" }, { type: "italic" }] },
                           { type: "text", text: "def", marks: [{ type: "italic" }] },
                           { type: "text", text: "ghi", marks: [] }
                         ])
  end

  # Known defect: style that starts mid-text is lost for the first segment
  it "handles BOLD [0,6) + ITALIC [3,9) — italic starting at 3 is picked up only after bold ends" do
    result = convert(
      text: "abcdefghi",
      inline_style_ranges: [
        { style: "BOLD", offset: 0, length: 6 },
        { style: "ITALIC", offset: 3, length: 6 }
      ]
    )
    expect(result).to eq([
                           { type: "text", text: "abcdef", marks: [{ type: "bold" }] },
                           { type: "text", text: "ghi", marks: [{ type: "italic" }] }
                         ])
  end

  # Known defect: style starting after position 0 is lost
  it "handles BOLD [3,6) in 'abcdef' — style is lost because no range covers position 0" do
    result = convert(
      text: "abcdef",
      inline_style_ranges: [{ style: "BOLD", offset: 3, length: 3 }]
    )
    expect(result).to eq([
                           { type: "text", text: "abcdef", marks: [] }
                         ])
  end

  it "handles CODE and LINK entity [0,4) in 'here now'" do
    entity_map = {
      "0": { type: "LINK", data: { url: "https://example.com" } }
    }
    result = convert(
      text: "here now",
      inline_style_ranges: [{ style: "CODE", offset: 0, length: 4 }],
      entity_ranges: [{ key: "0", offset: 0, length: 4 }],
      entity_map: entity_map
    )
    expect(result).to eq([
                           { type: "text", text: "here", marks: [{ type: "code" }, { type: "link", attrs: { href: "https://example.com" } }] },
                           { type: "text", text: " now", marks: [] }
                         ])
  end

  it "non-LINK entity cuts text but gives no mark" do
    entity_map = {
      "0": { type: "MENTION", data: { name: "John" } }
    }
    result = convert(
      text: "hello world",
      entity_ranges: [{ key: "0", offset: 0, length: 5 }],
      entity_map: entity_map
    )
    expect(result).to eq([
                           { type: "text", text: "hello", marks: [] },
                           { type: "text", text: " world", marks: [] }
                         ])
  end

  it "two overlapping LINK entities — each piece gets the first covering link" do
    entity_map = {
      "0": { type: "LINK", data: { url: "https://first.com" } },
      "1": { type: "LINK", data: { url: "https://second.com" } }
    }
    result = convert(
      text: "abcdefgh",
      entity_ranges: [
        { key: "0", offset: 0, length: 5 },
        { key: "1", offset: 3, length: 5 }
      ],
      entity_map: entity_map
    )
    expect(result).to eq([
                           { type: "text", text: "abcde", marks: [{ type: "link", attrs: { href: "https://first.com" } }] },
                           { type: "text", text: "fgh", marks: [{ type: "link", attrs: { href: "https://second.com" } }] }
                         ])
  end

  it "entity without a record in the map raises NoMethodError" do
    expect do
      convert(
        text: "hello",
        entity_ranges: [{ key: "99", offset: 0, length: 5 }],
        entity_map: {}
      )
    end.to raise_error(NoMethodError)
  end

  it "handles CUSTOM_COLOR_#a1b2c3 as textStyle with color" do
    result = convert(
      text: "colored",
      inline_style_ranges: [{ style: "CUSTOM_COLOR_#a1b2c3", offset: 0, length: 7 }]
    )
    expect(result).to eq([
                           { type: "text", text: "colored", marks: [{ type: "textStyle", attrs: { color: "#a1b2c3" } }] }
                         ])
  end
end
