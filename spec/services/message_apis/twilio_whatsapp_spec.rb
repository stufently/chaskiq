# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Twilio WhatsApp From field" do
  it "includes whatsapp: prefix in the From field" do
    source = Rails.root.join("app/services/message_apis/twilio/api.rb").read
    expect(source).to include('whatsapp:')
  end
end
