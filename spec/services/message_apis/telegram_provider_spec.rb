# frozen_string_literal: true

require "rails_helper"

RSpec.describe MessageApis::Telegram::Api do
  it "has PROVIDER set to 'telegram'" do
    expect(described_class::PROVIDER).to eq("telegram")
  end
end
