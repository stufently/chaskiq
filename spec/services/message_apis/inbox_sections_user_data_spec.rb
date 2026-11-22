# frozen_string_literal: true

require "rails_helper"

RSpec.describe MessageApis::InboxSections::Presenter, ".user_data" do
  it "returns the full data-table array" do
    expected = [
      {
        type: "data-table",
        items: [
          { type: "field-value", field: "Key", value: "Value 1" },
          { type: "field-value", field: "Key", value: "Value 2" },
          {
            type: "field-value",
            field: "Key",
            value: "Value 3 which is a very long value that will exhibit different behaviours to the other values"
          }
        ]
      }
    ]
    expect(described_class.user_data).to eq(expected)
  end
end
