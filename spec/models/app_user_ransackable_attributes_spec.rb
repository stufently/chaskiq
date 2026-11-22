# frozen_string_literal: true

require "rails_helper"

RSpec.describe AppUser, ".ransackable_attributes" do
  let(:expected) do
    %w[
      app_id browser browser_language browser_version city company_name company_size country country_code
      created_at email facebook first_name first_seen full_name gender id id_value ip job_title key lang
      last_contacted last_heard_from last_name last_seen last_visited_at lat linkedin lng name organization os
      os_version phone postal privacy_consent properties referrer region region_code session_id signed_up state
      subscription_state timezone twitter type updated_at web_sessions
    ]
  end

  it "returns the full list of 50 ransackable attribute names in order" do
    expect(AppUser.ransackable_attributes).to eq(expected)
  end

  it "returns the same list when called with an argument" do
    expect(AppUser.ransackable_attributes(nil)).to eq(expected)
  end
end
