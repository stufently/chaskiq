# frozen_string_literal: true

require "rails_helper"
require "base64"
require "json"

RSpec.describe PHP do
  reference = JSON.parse(Rails.root.join("spec/fixtures/php_serialize_1_2.json").read)

  reference.fetch("vectors").each do |vector|
    it "preserves the php_serialize 1.2 format for #{vector.fetch('name')}" do
      wire = Base64.strict_decode64(vector.fetch("serialized_base64"))
      expect(described_class.serialize(vector.fetch("input"), true).b).to eq(wire)

      wire.force_encoding(Encoding::UTF_8)
      expect(described_class.unserialize(wire)).to eql(vector.fetch("decoded"))
      expect(described_class.unserialize(wire, true)).to eql(vector.fetch("decoded_assoc"))
    end
  end
end
