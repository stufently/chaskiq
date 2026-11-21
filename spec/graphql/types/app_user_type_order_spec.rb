# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::AppUserType, type: :graphql do
  let(:app) { FactoryBot.create(:app) }
  let(:agent) { app.add_agent({ email: "agent@test.cl" }).agent }
  let(:app_user) { app.add_user(email: "user@test.cl", first_name: "User") }

  let(:context) { { current_user: agent } }
  let(:type_instance) { Types::AppUserType.send(:new, app_user, context) }

  describe "#visits" do
    it "returns visits ordered by id desc" do
      visit1 = Visit.create!(app_user: app_user, app: app)
      visit2 = Visit.create!(app_user: app_user, app: app)
      visit3 = Visit.create!(app_user: app_user, app: app)

      result = type_instance.visits(page: 1, per: 10)
      ids = result.map(&:id)
      expect(ids).to eq([visit3.id, visit2.id, visit1.id])
    end
  end

  describe "#conversations" do
    it "returns conversations ordered by updated_at desc" do
      conv1 = app.start_conversation(message: { html_content: "first" }, from: app_user)
      conv2 = app.start_conversation(message: { html_content: "second" }, from: app_user)

      # Update conv1's updated_at to be later
      conv1.update_column(:updated_at, 1.hour.from_now)

      result = type_instance.conversations(page: 1, per: 10)
      ids = result.map(&:id)
      expect(ids).to eq([conv1.id, conv2.id])
    end
  end
end
