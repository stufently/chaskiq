# frozen_string_literal: true

require "rails_helper"

RSpec.describe App, type: :model do
  let(:app) { FactoryBot.create(:app) }

  before do
    app.update!(timezone: "UTC", team_schedule: [{ "day" => "tue", "from" => "01:00", "to" => "01:30" }])
  end

  describe "#availability" do
    it "returns a Biz::Schedule" do
      expect(app.availability).to be_a(Biz::Schedule)
    end

    it "returns the same object on subsequent calls (memoization)" do
      first = app.availability
      second = app.availability
      expect(second).to equal(first)
    end
  end

  describe "#in_business_hours?" do
    it "returns true during business hours" do
      # Tuesday 2019-09-03 01:15 UTC, schedule: tue 01:00-01:30
      expect(app.in_business_hours?(Time.utc(2019, 9, 3, 1, 15))).to eq(true)
    end

    it "returns false outside business hours" do
      # Tuesday 2019-09-03 02:15 UTC, outside tue 01:00-01:30
      expect(app.in_business_hours?(Time.utc(2019, 9, 3, 2, 15))).to eq(false)
    end
  end
end
