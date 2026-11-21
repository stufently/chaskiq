# frozen_string_literal: true

require "rails_helper"

RSpec.describe MessageApis::Csat::Api do
  let(:app) { FactoryBot.create(:app) }
  let(:app_package) { double(icon: double, name: "Csat") }
  let(:integration) { double(app: app, app_package: app_package) }

  describe "#report general" do
    it "returns labels from csat_buttons options and correct percentages" do
      custom_counts = [
        double(val: "2", freq: 1),
        double(val: "4", freq: 3)
      ]

      conversation_events = double
      allow(app).to receive(:conversation_events).and_return(conversation_events)
      allow(conversation_events).to receive(:custom_counts).with("plugins.csat", "val").and_return(custom_counts)

      result = described_class.new(config: {}).report("general", integration, nil)

      buttons = MessageApis::Csat::Presenter.csat_buttons[:options]
      label2 = buttons.find { |d| d[:id] == "2" }[:text]
      label4 = buttons.find { |d| d[:id] == "4" }[:text]

      values = result[:values]
      expect(values.size).to eq(2)

      v2 = values.find { |v| v[:name] == "2" }
      expect(v2[:label]).to eq(label2)
      expect(v2[:value]).to eq("25.0%")

      v4 = values.find { |v| v[:name] == "4" }
      expect(v4[:label]).to eq(label4)
      expect(v4[:value]).to eq("75.0%")
    end
  end
end
