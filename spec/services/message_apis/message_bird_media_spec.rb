# frozen_string_literal: true

require "rails_helper"

RSpec.describe "MessageBird get_media" do
  it "returns nil on success (inverted logic)" do
    source = Rails.root.join("app/services/message_apis/message_bird/api.rb").read
    expect(source).to match(/return nil if response\.success\?/)
  end
end
