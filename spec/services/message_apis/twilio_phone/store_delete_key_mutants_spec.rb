# frozen_string_literal: true

require "rails_helper"

RSpec.describe MessageApis::TwilioPhone::Store do
  let(:conv_key) { "mfxb-store-#{SecureRandom.hex(4)}" }

  after { described_class.hash(conv_key).remove }

  describe ".delete_key (mutant-killing)" do
    it "X01: returns the HDEL count for a present field and 0 for an absent field" do
      described_class.set(conv_key, "a", "1")

      expect(described_class.delete_key(conv_key, "a")).to eq(1)
      expect(described_class.delete_key(conv_key, "absent")).to eq(0)
    end

    it "X04: deletes a field that holds a blank value" do
      described_class.set(conv_key, "a", "")

      described_class.delete_key(conv_key, "a")

      expect(described_class.get_values(conv_key)).not_to have_key("a")
    end
  end
end
