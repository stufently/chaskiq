# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicationController do
  describe "#cookie_namespace" do
    it "returns a symbol with the app key stripped of dashes" do
      controller = described_class.new
      controller.instance_variable_set(:@app, App.new(key: "ab-cd-ef"))
      expect(controller.send(:cookie_namespace)).to eq(:chaskiq_session_id_abcdef)
    end
  end
end
