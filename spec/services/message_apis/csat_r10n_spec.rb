# frozen_string_literal: true

require "rails_helper"

RSpec.describe MessageApis::Csat::Api, type: :service do
  let(:app) { FactoryBot.create(:app) }
  let(:app_package) { double(icon: double, name: "Csat") }
  let(:integration) { double(app: app, app_package: app_package) }
  let(:api) { described_class.new(config: {}) }

  let(:buttons) { MessageApis::Csat::Presenter.csat_buttons[:options] }

  describe "#report general" do
    it "returns no rating rows when the app has no CSAT events" do
      result = api.report("general", integration, nil)

      expect(result).to eq(
        id: "csat-plugin",
        title: "Conversation ratings",
        subtitle: "csat plugin",
        package_icon: app_package.icon,
        package_name: app_package.name,
        values: []
      )
    end

    it "returns labels from csat_buttons with correct percentages" do
      custom_counts = [
        double(val: "2", freq: 1),
        double(val: "4", freq: 3)
      ]
      conversation_events = double
      allow(app).to receive(:conversation_events).and_return(conversation_events)
      allow(conversation_events)
        .to receive(:custom_counts).with("plugins.csat", "val").and_return(custom_counts)

      result = api.report("general", integration, nil)

      expect(result[:id]).to eq("csat-plugin")
      expect(result[:title]).to eq("Conversation ratings")
      expect(result[:subtitle]).to eq("csat plugin")
      expect(result[:package_icon]).to eq(app_package.icon)
      expect(result[:package_name]).to eq(app_package.name)

      values = result[:values]
      expect(values.size).to eq(2)

      v2 = values.find { |v| v[:name] == "2" }
      expect(v2[:label]).to eq(buttons.find { |d| d[:id] == "2" }[:text])
      expect(v2[:value]).to eq("25.0%")
      expect(v2[:value2]).to eq("1 events")

      v4 = values.find { |v| v[:name] == "4" }
      expect(v4[:label]).to eq(buttons.find { |d| d[:id] == "4" }[:text])
      expect(v4[:value]).to eq("75.0%")
      expect(v4[:value2]).to eq("3 events")
    end

    it "preserves the order from custom_counts" do
      custom_counts = [
        double(val: "5", freq: 2),
        double(val: "1", freq: 2)
      ]
      conversation_events = double
      allow(app).to receive(:conversation_events).and_return(conversation_events)
      allow(conversation_events)
        .to receive(:custom_counts).with("plugins.csat", "val").and_return(custom_counts)

      result = api.report("general", integration, nil)
      names = result[:values].pluck(:name)
      expect(names).to eq(%w[5 1])
    end

    it "uses ceil(1) for rounding" do
      custom_counts = [
        double(val: "1", freq: 1),
        double(val: "2", freq: 2)
      ]
      conversation_events = double
      allow(app).to receive(:conversation_events).and_return(conversation_events)
      allow(conversation_events)
        .to receive(:custom_counts).with("plugins.csat", "val").and_return(custom_counts)

      result = api.report("general", integration, nil)
      v1 = result[:values].find { |v| v[:name] == "1" }
      v2 = result[:values].find { |v| v[:name] == "2" }
      # 1/3*100 = 33.333... -> ceil(1) = 33.4
      expect(v1[:value]).to eq("33.4%")
      # 2/3*100 = 66.666... -> ceil(1) = 66.7
      expect(v2[:value]).to eq("66.7%")
    end
  end

  describe "#report events_table" do
    it "filters real events and returns rows on the second page" do
      participant = app.add_user(email: "r10n-csat@test.cl")
      conversation = app.conversations.create!(main_participant: participant)
      ratings = Array.new(11) do |index|
        conversation.events.create!(
          action: "plugins.csat",
          properties: { value: "4", label: "Good", comment: "Rating #{index}" }
        )
      end
      conversation.events.create!(action: "other.event", properties: { value: "0" })

      first = api.report("events_table", integration, { page: 1 })
      second = api.report("events_table", integration, { page: 2 })
      rows = first[:collection] + second[:collection]

      expect(first[:collection].length).to eq(10)
      expect(second[:collection].length).to eq(1)
      expect(rows).to match_array(ratings.map(&:serialize_properties))
      expect(second[:columns]).to eq([
                                       { field: "value", title: "value" },
                                       { field: "label", title: "label" },
                                       { field: "comment", title: "comment" }
                                     ])
      expect(second[:meta]).to eq({
                                    current_page: 2,
                                    next_page: nil,
                                    prev_page: 1,
                                    total_pages: 2,
                                    total_count: 11
                                  })
    end
  end

  describe "#report other paths" do
    it "returns 100 for custom" do
      expect(api.report("custom", integration, nil)).to eq(100)
    end

    it "returns nil for an unknown path" do
      expect(api.report("nonexistent", integration, nil)).to be_nil
    end
  end
end
