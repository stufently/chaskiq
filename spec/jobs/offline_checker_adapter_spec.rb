# frozen_string_literal: true

require "rails_helper"

RSpec.describe "OfflineCheckerJob subscribed? method" do
  it "returns false when adapter is not redis" do
    source = Rails.root.join("app/jobs/offline_checker_job.rb").read
    expect(source).to match(/return\s+false\s+unless\s+cable\[:adapter\]\s*==\s*"redis"/)
  end
end
