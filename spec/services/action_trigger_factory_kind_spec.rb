# frozen_string_literal: true

require "rails_helper"

RSpec.describe ActionTriggerFactory do
  let(:app) { FactoryBot.create(:app) }

  describe ".infer_for paths" do
    context "when user is AppUser" do
      let(:user) { app.add_user(email: "user@example.com") }

      before { user.update!(lang: "en") }

      it "typical_reply_time path contains step uuid 1" do
        result = described_class.infer_for(app: app, user: user)
        path = result.paths.find { |p| p[:title] == "typical_reply_time" }
        uids = path[:steps].pluck(:step_uid)
        expect(uids).to eq([1])
      end
    end

    context "when user is Lead" do
      let(:user) { app.add_lead({}) }

      before { user.update!(lang: "en") }

      it "typical_reply_time path contains step uuids 5 and 6" do
        result = described_class.infer_for(app: app, user: user)
        path = result.paths.find { |p| p[:title] == "typical_reply_time" }
        uids = path[:steps].pluck(:step_uid)
        expect(uids).to eq([5, 6])
      end
    end

    context "when user is Visitor" do
      let(:user) { app.add_anonymous_user({}) }

      before { user.update!(lang: "en") }

      it "typical_reply_time path contains step uuids 5 and 6" do
        result = described_class.infer_for(app: app, user: user)
        path = result.paths.find { |p| p[:title] == "typical_reply_time" }
        uids = path[:steps].pluck(:step_uid)
        expect(uids).to eq([5, 6])
      end
    end
  end

  describe ".infer_for yes path with email_requirement" do
    let(:user) { app.add_lead({}) }

    before { user.update!(lang: "en") }

    context "when email_requirement is office and not in business hours" do
      before do
        app.update!(email_requirement: "office")
        allow(app).to receive(:in_business_hours?).and_return(false)
      end

      it "yes path contains step uuids 7, 2, 3, 4" do
        result = described_class.infer_for(app: app, user: user)
        path = result.paths.find { |p| p[:title] == "yes" }
        uids = path[:steps].pluck(:step_uid)
        expect(uids).to eq([7, 2, 3, 4])
      end
    end

    context "when email_requirement is office and in business hours" do
      before do
        app.update!(email_requirement: "office")
        allow(app).to receive(:in_business_hours?).and_return(true)
      end

      it "yes path contains step uuids 7, 4" do
        result = described_class.infer_for(app: app, user: user)
        path = result.paths.find { |p| p[:title] == "yes" }
        uids = path[:steps].pluck(:step_uid)
        expect(uids).to eq([7, 4])
      end
    end
  end

  describe ".find_task" do
    let(:user) { app.add_lead({}) }

    before { user.update!(lang: "en") }

    it "returns the no path when step is 8" do
      _trigger, path = described_class.find_task(
        data: { "trigger" => "infer", "step" => "8" },
        app: app,
        app_user: user
      )
      expect(path["title"]).to eq("no")
    end

    it "returns the yes path when step is 4" do
      _trigger, path = described_class.find_task(
        data: { "trigger" => "infer", "step" => "4" },
        app: app,
        app_user: user
      )
      expect(path["title"]).to eq("yes")
    end
  end
end
