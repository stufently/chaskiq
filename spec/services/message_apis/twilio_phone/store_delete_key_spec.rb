# frozen_string_literal: true

require "rails_helper"

RSpec.describe MessageApis::TwilioPhone::Store do
  let(:conv_key) { "fxb-#{SecureRandom.hex(4)}" }

  after { described_class.hash(conv_key).remove }

  describe ".delete_key" do
    it "deletes the requested field and preserves the other field" do
      described_class.set(conv_key, "a", "1")
      described_class.set(conv_key, "b", "2")

      described_class.delete_key(conv_key, "a")

      expect(described_class.get(conv_key, "a")).to be_nil
      expect(described_class.get(conv_key, "b")).to eq("2")
    end

    it "preserves the stored fields when the requested field is absent" do
      described_class.set(conv_key, "b", "2")

      described_class.delete_key(conv_key, "a")

      expect(described_class.get_values(conv_key)).to eq({ "b" => "2" })
    end
  end
end
