# frozen_string_literal: true

require "rails_helper"

RSpec.describe Nightfury do
  describe ".namespace" do
    it "defaults to :nf" do
      original = described_class.instance_variable_get(:@namespace)
      begin
        described_class.instance_variable_set(:@namespace, nil)
        expect(described_class.namespace).to eq(:nf)
      ensure
        described_class.instance_variable_set(:@namespace, original)
      end
    end
  end
end
