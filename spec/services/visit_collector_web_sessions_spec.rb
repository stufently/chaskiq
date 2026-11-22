# frozen_string_literal: true

require "rails_helper"

RSpec.describe VisitCollector, "#add_web_sessions" do
  include ActiveSupport::Testing::TimeHelpers

  let(:app) { FactoryBot.create(:app) }
  let(:user) { app.add_user(email: "visitor@example.com") }
  let(:now) { Time.zone.local(2026, 11, 21, 12, 0, 0) }

  before { travel_to(now) }

  def result(user)
    described_class.new(user: user).add_web_sessions
  end

  context "new user (first_seen, last_visited_at, web_sessions all nil)" do
    before { user.update_columns(first_seen: nil, last_visited_at: nil, web_sessions: nil) }

    it "returns all four keys with web_sessions 1" do
      res = result(user)
      expect(res.keys).to eq(%i[first_seen last_seen web_sessions last_visited_at])
      expect(res[:web_sessions]).to eq(1)
      expect(res[:first_seen]).to eq(now)
      expect(res[:last_seen]).to eq(now)
      expect(res[:last_visited_at]).to eq(now)
    end
  end

  context "known user without last_visited_at (web_sessions: 4)" do
    before do
      user.update_columns(first_seen: 1.day.ago, last_visited_at: nil, web_sessions: 4)
    end

    it "returns last_seen, web_sessions 5, last_visited_at" do
      res = result(user)
      expect(res.keys).to eq(%i[last_seen web_sessions last_visited_at])
      expect(res[:web_sessions]).to eq(5)
      expect(res[:last_visited_at]).to eq(now)
    end
  end

  context "last visited 29 minutes ago" do
    before do
      user.update_columns(first_seen: 1.day.ago, last_visited_at: 29.minutes.ago, web_sessions: 3)
    end

    it "returns only last_seen" do
      res = result(user)
      expect(res.keys).to eq(%i[last_seen])
      expect(res[:last_seen]).to eq(now)
    end
  end

  context "10 minutes ago without first_seen" do
    before do
      user.update_columns(first_seen: nil, last_visited_at: 10.minutes.ago, web_sessions: 2)
    end

    it "returns first_seen and last_seen" do
      res = result(user)
      expect(res.keys).to eq(%i[first_seen last_seen])
      expect(res[:first_seen]).to eq(now)
      expect(res[:last_seen]).to eq(now)
    end
  end

  context "exactly 30 minutes ago" do
    before do
      user.update_columns(first_seen: 1.day.ago, last_visited_at: 30.minutes.ago, web_sessions: 5)
    end

    it "starts a new session" do
      res = result(user)
      expect(res.keys).to eq(%i[last_seen web_sessions last_visited_at])
      expect(res[:web_sessions]).to eq(6)
      expect(res[:last_visited_at]).to eq(now)
    end
  end

  context "3 hours ago without first_seen and web_sessions" do
    before do
      user.update_columns(first_seen: nil, last_visited_at: 3.hours.ago, web_sessions: nil)
    end

    it "returns all four keys" do
      res = result(user)
      expect(res.keys).to eq(%i[first_seen last_seen web_sessions last_visited_at])
      expect(res[:first_seen]).to eq(now)
      expect(res[:web_sessions]).to eq(1)
      expect(res[:last_seen]).to eq(now)
      expect(res[:last_visited_at]).to eq(now)
    end
  end
end
