# frozen_string_literal: true

require "rails_helper"

RSpec.describe Role do
  it "returns the avatar URL of its agent" do
    role = described_class.new(agent: Agent.new(email: "agent@example.com"))

    expect(role.avatar_url).to eq(role.agent.avatar_url)
  end
end
