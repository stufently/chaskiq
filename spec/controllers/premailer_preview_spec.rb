# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicationController, type: :controller do
  let(:chat_app) { FactoryBot.create(:app) }

  it "assigns @campaign from the same app" do
    campaign = FactoryBot.create(:campaign, app: chat_app, html_content: "<p>hi</p>")
    get :preview, params: { app: chat_app.key, id: campaign.id }
    expect(response).to have_http_status(200)
    expect(controller.instance_variable_get(:@campaign)).to eq(campaign)
  end

  it "raises RecordNotFound for a campaign of another app" do
    other_app = FactoryBot.create(:app)
    other_campaign = FactoryBot.create(:campaign, app: other_app, html_content: "<p>hi</p>")
    expect do
      get :preview, params: { app: chat_app.key, id: other_campaign.id }
    end.to raise_error(ActiveRecord::RecordNotFound)
  end
end
