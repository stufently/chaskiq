# frozen_string_literal: true

require "rails_helper"

RSpec.describe AppUserEventJob, type: :job do
  let(:app) { FactoryBot.create(:app) }
  let(:user) { app.add_user(email: "visitor@example.com") }

  describe "#perform" do
    it "passes the app user to the tour broadcast" do
      allow(Tour).to receive(:broadcast_tour_to_user).and_return(true)

      described_class.perform_now(app_key: app.key, user_id: user.id)

      expect(Tour).to have_received(:broadcast_tour_to_user).with(user)
    end

    it "passes the app user to the bot task when the tour does not broadcast" do
      allow(Tour).to receive(:broadcast_tour_to_user).and_return(nil)
      allow(BotTask).to receive(:broadcast_task_to_user).and_return(true)

      described_class.perform_now(app_key: app.key, user_id: user.id)

      expect(BotTask).to have_received(:broadcast_task_to_user).with(user)
    end
  end
end
