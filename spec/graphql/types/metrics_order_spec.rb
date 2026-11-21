# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Metrics ordering", type: :graphql do
  let(:app) { FactoryBot.create(:app) }
  let(:agent) { app.add_agent({ email: "agent@test.cl" }).agent }
  let(:app_user) { app.add_user(email: "user@test.cl", first_name: "User") }

  describe "Types::BotTaskType#metrics" do
    it "returns metrics ordered by id desc" do
      bot_task = BotTask.create!(app: app, name: "Test Bot", state: "enabled")

      metric1 = Metric.create!(trackable: bot_task, app_user: app_user, action: "open")
      metric2 = Metric.create!(trackable: bot_task, app_user: app_user, action: "open")

      context = { current_user: agent }
      type_instance = Types::BotTaskType.send(:new, bot_task, context)

      result = type_instance.metrics(page: 1, per: 20)
      ids = result.map(&:id)
      expect(ids).to eq([metric2.id, metric1.id])
    end
  end

  describe "Types::CampaignType#metrics" do
    it "returns metrics ordered by id desc" do
      campaign = FactoryBot.create(:campaign, app: app)

      metric1 = Metric.create!(trackable: campaign, app_user: app_user, action: "open")
      metric2 = Metric.create!(trackable: campaign, app_user: app_user, action: "open")

      context = { current_user: agent }
      type_instance = Types::CampaignType.send(:new, campaign, context)

      result = type_instance.metrics(page: 1, per: 20)
      ids = result.map(&:id)
      expect(ids).to eq([metric2.id, metric1.id])
    end
  end
end
