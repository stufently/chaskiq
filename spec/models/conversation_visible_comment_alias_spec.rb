# frozen_string_literal: true

require "rails_helper"

RSpec.describe Conversation do
  describe "#has_user_visible_comment?" do
    it "returns true when latest_user_visible_comment_at is set" do
      expect(described_class.new(latest_user_visible_comment_at: Time.zone.now).has_user_visible_comment?).to eq(true)
    end

    it "returns false when latest_user_visible_comment_at is nil" do
      expect(described_class.new(latest_user_visible_comment_at: nil).has_user_visible_comment?).to eq(false)
    end
  end

  describe "renamed" do
    describe "#user_visible_comment?" do
      it "returns true when latest_user_visible_comment_at is set" do
        expect(described_class.new(latest_user_visible_comment_at: Time.zone.now).user_visible_comment?).to eq(true)
      end

      it "returns false when latest_user_visible_comment_at is nil" do
        expect(described_class.new(latest_user_visible_comment_at: nil).user_visible_comment?).to eq(false)
      end
    end
  end
end
