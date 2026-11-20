# frozen_string_literal: true

require "rails_helper"

RSpec.describe AppUserEventJob, type: :job do
  let(:app) { FactoryBot.create(:app) }
  let(:user) { app.add_user(email: "user@test.cl") }

  describe "#perform" do
    it "returns true when Tour broadcasts and does not call BotTask" do
      allow(Tour).to receive(:broadcast_tour_to_user).and_return(true)
      allow(BotTask).to receive(:broadcast_task_to_user)

      result = described_class.perform_now(app_key: app.key, user_id: user.id)
      expect(result).to eq(true)
      expect(BotTask).not_to have_received(:broadcast_task_to_user)
    end

    it "falls through to UserAutoMessage when Tour and BotTask return nil" do
      allow(Tour).to receive(:broadcast_tour_to_user).and_return(nil)
      allow(BotTask).to receive(:broadcast_task_to_user).and_return(nil)
      allow(UserAutoMessage).to receive(:broadcast_message_to_user).and_return("auto_msg_result")

      result = described_class.perform_now(app_key: app.key, user_id: user.id)
      expect(result).to eq("auto_msg_result")
      expect(UserAutoMessage).to have_received(:broadcast_message_to_user).with(user)
    end

    it "raises RecordNotFound for user from a different app" do
      other_app = FactoryBot.create(:app)
      other_user = other_app.add_user(email: "other@test.cl")

      expect do
        described_class.perform_now(app_key: app.key, user_id: other_user.id)
      end.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
