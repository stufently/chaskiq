# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agent, ".ransackable_attributes" do
  let(:expected) do
    %w[
      available bot confirmation_sent_at confirmation_token confirmed_at
      created_at current_sign_in_at current_sign_in_ip email
      encrypted_password failed_attempts id id_value invitation_accepted_at
      invitation_created_at invitation_limit invitation_sent_at
      invitation_token invitations_count invited_by_id invited_by_type key
      last_sign_in_at last_sign_in_ip locked_at properties
      remember_created_at reset_password_sent_at reset_password_token
      sign_in_count unconfirmed_email unlock_token updated_at
    ]
  end

  it "returns the full list of 36 attributes" do
    expect(Agent.ransackable_attributes).to eq(expected)
  end

  it "returns the same list with an argument" do
    expect(Agent.ransackable_attributes(nil)).to eq(expected)
  end
end
