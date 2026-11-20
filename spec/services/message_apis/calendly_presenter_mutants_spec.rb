# frozen_string_literal: true

require "rails_helper"

RSpec.describe MessageApis::Calendly::Presenter do
  describe ".initialize_hook" do
    let(:values) do
      { url: "https://calendly.com/example", invitation_text: "Choose a time", label: "Book a meeting" }
    end

    it "returns an initialization response with the configured values" do
      result = described_class.initialize_hook(ctx: { values: values })

      expect(result).to include(kind: "initialize", values: values)
    end

    it "renders the configured button label and booking frame" do
      result = described_class.initialize_hook(ctx: { values: values })

      expect(result[:definitions]).to include(
        a_hash_including(label: "Book a meeting",
                         type: "button",
                         action: { type: "frame", url: "/package_iframe_internal/Calendly" })
      )
    end
  end
end
