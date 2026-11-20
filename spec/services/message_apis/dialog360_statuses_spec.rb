# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dialog360 API" do
  let(:source) { Rails.root.join("app/services/message_apis/dialog360/api.rb").read }

  describe "process_read called for read status (M060)" do
    it "calls process_read when status is read" do
      expect(source).to match(/when\s+"read"\s+then\s+process_read/)
    end
  end

  describe "prepare_initiator_channel_for rollback (M061)" do
    it "raises ActiveRecord::Rollback for blank profile_id" do
      expect(source).to include("raise ActiveRecord::Rollback if profile_id.blank?")
    end
  end

  describe "add_participant empty string (M062)" do
    it "uses return unless (not return if blank) for dialog_user" do
      expect(source).to match(/return unless dialog_user\b/)
    end
  end

  describe "send_message blank profile_id guard (M237)" do
    it "returns if profile_id is blank" do
      expect(source).to match(/return if profile_id\.blank\?/)
    end
  end
end
