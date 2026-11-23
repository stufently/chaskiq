# frozen_string_literal: true

require "rails_helper"

RSpec.describe PluginSchemaValidator do
  describe "#valid?" do
    it "returns true for valid text elements" do
      validator = described_class.new([
                                        { type: "text", text: "hello", style: "paragraph" },
                                        { type: "text", text: "world", style: "header" }
                                      ])
      expect(validator.valid?).to be true
    end

    it "returns false when text element is missing required text field" do
      validator = described_class.new([
                                        { type: "text", style: "paragraph" }
                                      ])
      expect(validator.valid?).to be false
    end

    it "returns false when text element has invalid style" do
      validator = described_class.new([
                                        { type: "text", text: "hello", style: "invalid-style" }
                                      ])
      expect(validator.valid?).to be false
    end

    it "returns true for valid button with action" do
      validator = described_class.new([
                                        {
                                          id: "btn1",
                                          name: "button",
                                          label: "Click",
                                          type: "button",
                                          action: { type: "submit" }
                                        }
                                      ])
      expect(validator.valid?).to be true
    end

    it "returns false for button without id" do
      validator = described_class.new([
                                        {
                                          name: "button",
                                          label: "Click",
                                          type: "button",
                                          action: { type: "submit" }
                                        }
                                      ])
      expect(validator.valid?).to be false
    end

    it "returns false for button with invalid action type" do
      validator = described_class.new([
                                        {
                                          id: "btn1",
                                          type: "button",
                                          action: { type: "invalid-action" }
                                        }
                                      ])
      expect(validator.valid?).to be false
    end

    it "returns true for valid image element" do
      validator = described_class.new([
                                        {
                                          type: "image",
                                          url: "https://example.com/image.png",
                                          height: 100,
                                          width: 200
                                        }
                                      ])
      expect(validator.valid?).to be true
    end

    it "returns false for image without required dimensions" do
      validator = described_class.new([
                                        { type: "image", url: "https://example.com/image.png" }
                                      ])
      expect(validator.valid?).to be false
    end

    it "returns true for valid spacer element" do
      validator = described_class.new([
                                        { type: "spacer", size: "m" }
                                      ])
      expect(validator.valid?).to be true
    end

    it "returns true for valid data-table element" do
      validator = described_class.new([
                                        {
                                          type: "data-table",
                                          items: [
                                            { type: "field-value", field: "Key", value: "Value" }
                                          ]
                                        }
                                      ])
      expect(validator.valid?).to be true
    end

    it "returns false for data-table with invalid items" do
      validator = described_class.new([
                                        {
                                          type: "data-table",
                                          items: [
                                            { type: "field-value" }
                                          ]
                                        }
                                      ])
      expect(validator.valid?).to be false
    end

    it "returns true for valid input element" do
      validator = described_class.new([
                                        {
                                          type: "input",
                                          id: "input1",
                                          label: "Name",
                                          placeholder: "Enter name"
                                        }
                                      ])
      expect(validator.valid?).to be true
    end

    it "returns false for input without id" do
      validator = described_class.new([
                                        { type: "input", label: "Name" }
                                      ])
      expect(validator.valid?).to be false
    end

    it "returns true for valid list element" do
      validator = described_class.new([
                                        {
                                          type: "list",
                                          items: [
                                            { type: "item", id: "item1", title: "Item 1" }
                                          ]
                                        }
                                      ])
      expect(validator.valid?).to be true
    end

    it "returns false for list with invalid items" do
      validator = described_class.new([
                                        {
                                          type: "list",
                                          items: [
                                            { type: "item", id: "item1" }
                                          ]
                                        }
                                      ])
      expect(validator.valid?).to be false
    end

    it "returns true for valid single-select element" do
      validator = described_class.new([
                                        {
                                          type: "single-select",
                                          options: [
                                            { type: "option", id: "opt1", text: "Option 1" }
                                          ]
                                        }
                                      ])
      expect(validator.valid?).to be true
    end

    it "returns true for valid checkbox element" do
      validator = described_class.new([
                                        {
                                          type: "checkbox",
                                          id: "check1",
                                          options: [
                                            { type: "option", id: "opt1", text: "Option 1" }
                                          ]
                                        }
                                      ])
      expect(validator.valid?).to be true
    end

    it "returns true for valid dropdown element" do
      validator = described_class.new([
                                        {
                                          type: "dropdown",
                                          id: "drop1",
                                          label: "Select",
                                          options: [
                                            { type: "option", id: "opt1", text: "Option 1" }
                                          ]
                                        }
                                      ])
      expect(validator.valid?).to be true
    end

    it "returns true for valid frame element" do
      validator = described_class.new([
                                        { type: "frame", url: "https://example.com/frame" }
                                      ])
      expect(validator.valid?).to be true
    end

    it "returns false for frame without url" do
      validator = described_class.new([
                                        { type: "frame" }
                                      ])
      expect(validator.valid?).to be false
    end

    it "returns true for valid separator element" do
      validator = described_class.new([
                                        { type: "separator" }
                                      ])
      expect(validator.valid?).to be true
    end

    it "returns true for valid hidden element" do
      validator = described_class.new([
                                        { type: "hidden", id: "h1", name: "field", value: "secret" }
                                      ])
      expect(validator.valid?).to be true
    end

    it "returns true for mixed valid elements" do
      validator = described_class.new([
                                        { type: "text", text: "hello", style: "paragraph" },
                                        { type: "spacer", size: "m" },
                                        { type: "separator" }
                                      ])
      expect(validator.valid?).to be true
    end

    it "returns false when any element in mixed list is invalid" do
      validator = described_class.new([
                                        { type: "text", text: "hello", style: "paragraph" },
                                        { type: "frame" },
                                        { type: "separator" }
                                      ])
      expect(validator.valid?).to be false
    end

    it "returns true for empty elements array" do
      validator = described_class.new([])
      expect(validator.valid?).to be true
    end
  end

  describe "#schema" do
    it "creates BaseSchema objects for each element" do
      validator = described_class.new([
                                        { type: "text", text: "hello", style: "paragraph" },
                                        { type: "spacer" }
                                      ])
      expect(validator.schema.length).to eq(2)
      expect(validator.schema).to all(be_a(BaseSchema))
    end
  end
end

RSpec.describe BaseSchema do
  describe "#valid?" do
    it "delegates validation to the model" do
      schema = described_class.new({ type: "text", text: "hello", style: "paragraph" })
      expect(schema.valid?).to be true
    end

    it "returns false for invalid model" do
      schema = described_class.new({ type: "text", style: "paragraph" })
      expect(schema.valid?).to be false
    end
  end
end

RSpec.describe ActionSchema do
  describe "#valid?" do
    it "returns true for valid submit action" do
      action = described_class.new({ type: "submit" })
      expect(action.valid?).to be true
    end

    it "returns true for valid link action with url" do
      action = described_class.new({ type: "link", url: "https://example.com" })
      expect(action.valid?).to be true
    end

    it "returns false for link action without url" do
      action = described_class.new({ type: "link" })
      expect(action.valid?).to be false
    end

    it "returns true for valid content action with content_url" do
      action = described_class.new({ type: "content", content_url: "https://example.com/content" })
      expect(action.valid?).to be true
    end

    it "returns false for content action without content_url" do
      action = described_class.new({ type: "content" })
      expect(action.valid?).to be false
    end

    it "returns true for valid frame action with url" do
      action = described_class.new({ type: "frame", url: "https://example.com/frame" })
      expect(action.valid?).to be true
    end

    it "returns false for invalid action type" do
      action = described_class.new({ type: "invalid" })
      expect(action.valid?).to be false
    end
  end
end
