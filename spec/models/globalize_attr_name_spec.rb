# frozen_string_literal: true

require "rails_helper"

RSpec.describe GlobalizeAccessors, type: :model do
  describe "#localized_attr_name_for" do
    it "returns the localized attribute name with underscored locale" do
      app = FactoryBot.create(:app)
      expect(app.localized_attr_name_for(:title, :"pt-BR")).to eq("title_pt_br")
    end
  end
end
