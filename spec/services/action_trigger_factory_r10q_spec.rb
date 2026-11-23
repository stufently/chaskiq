# frozen_string_literal: true

require "rails_helper"

RSpec.describe ActionTriggerFactory do
  let(:app) { FactoryBot.create(:app) }
  let!(:bot_agent) { app.add_agent({ email: "bot@test.com", name: "Bot" }, bot: true).agent }

  around do |example|
    I18n.with_locale(I18n.locale) { example.run }
  end

  describe ".request_for_email" do
    subject { described_class.request_for_email(app: app) }

    it "has id request_for_email and after_delay 2" do
      expect(subject.id).to eq("request_for_email")
      expect(subject.after_delay).to eq(2)
    end

    it "has one path with steps for message, controls and ack message" do
      expect(subject.paths.size).to eq(1)
      uids = subject.paths.first[:steps].pluck(:step_uid)
      expect(uids).to eq([1, 2, 3])
    end

    it "has a data_retrieval controls step" do
      controls_step = subject.paths.first[:steps].find { |s| s[:step_uid] == 2 }
      expect(controls_step[:controls][:type]).to eq("data_retrieval")
    end

    it "has an assign follow action from lead_tasks_settings" do
      expect(subject.paths.first[:follow_actions]).to include(
        hash_including(key: "assign")
      )
    end
  end

  describe ".route_support" do
    subject { described_class.route_support(app: app) }

    it "has id route_support and three paths" do
      expect(subject.id).to eq("route_support")
      expect(subject.paths.size).to eq(3)
    end

    it "has a base path with ask_option controls and two buttons" do
      base = subject.paths.find { |p| p[:title] == "route_support" }
      controls = base[:steps].find { |s| s[:step_uid] == 2 }
      expect(controls[:controls][:type]).to eq("ask_option")
      expect(controls[:controls][:schema].size).to eq(2)
    end

    it "has yes and no paths with matching step uids from buttons" do
      yes_path = subject.paths.find { |p| p[:title] == "yes" }
      no_path = subject.paths.find { |p| p[:title] == "no" }
      expect(yes_path[:steps].first[:step_uid]).to eq(3)
      expect(no_path[:steps].first[:step_uid]).to eq(4)
    end
  end

  describe ".typical_reply_time" do
    it "raises when the configured I18n version receives positional interpolation options" do
      expect { described_class.typical_reply_time(app: app) }
        .to raise_error(ArgumentError, /wrong number of arguments/)
    end
  end

  describe ".infer_for" do
    context "with AppUser" do
      let(:user) { app.add_user(email: "user@example.com") }

      before { user.update!(lang: "en") }

      it "first path has step uid 1 (reply_soon only)" do
        result = described_class.infer_for(app: app, user: user)
        uids = result.paths.first[:steps].pluck(:step_uid)
        expect(uids).to eq([1])
      end

      it "does not use lead follow actions on the first path" do
        allow(app).to receive(:lead_tasks_settings).and_return({ "routing" => "close" })
        result = described_class.infer_for(app: app, user: user)
        expect(result.paths.first[:follow_actions]).to be_empty
      end

      it "yes path has step uids 7 and 4 (no email_requirement for user with email)" do
        result = described_class.infer_for(app: app, user: user)
        yes_path = result.paths.find { |p| p[:title] == "yes" }
        expect(yes_path[:steps].pluck(:step_uid)).to eq([7, 4])
      end
    end

    context "with Lead without email" do
      let(:user) { app.add_lead({}) }

      before { user.update!(lang: "en") }

      it "first path includes route_support steps 5 and 6" do
        result = described_class.infer_for(app: app, user: user)
        uids = result.paths.first[:steps].pluck(:step_uid)
        expect(uids).to include(5, 6)
      end

      it "yes path includes email_requirement steps 2 and 3 when email_requirement is Always" do
        app.update!(email_requirement: "Always")
        result = described_class.infer_for(app: app, user: user)
        yes_path = result.paths.find { |p| p[:title] == "yes" }
        expect(yes_path[:steps].pluck(:step_uid)).to eq([7, 2, 3, 4])
      end

      it "yes path includes email_requirement when office and outside business hours" do
        app.update!(email_requirement: "office")
        allow(app).to receive(:in_business_hours?).and_return(false)
        result = described_class.infer_for(app: app, user: user)
        yes_path = result.paths.find { |p| p[:title] == "yes" }
        expect(yes_path[:steps].pluck(:step_uid)).to eq([7, 2, 3, 4])
      end

      it "yes path skips email_requirement when office and inside business hours" do
        app.update!(email_requirement: "office")
        allow(app).to receive(:in_business_hours?).and_return(true)
        result = described_class.infer_for(app: app, user: user)
        yes_path = result.paths.find { |p| p[:title] == "yes" }
        expect(yes_path[:steps].pluck(:step_uid)).to eq([7, 4])
      end

      it "yes path skips email_requirement when never" do
        app.update!(email_requirement: "never")
        result = described_class.infer_for(app: app, user: user)
        yes_path = result.paths.find { |p| p[:title] == "yes" }
        expect(yes_path[:steps].pluck(:step_uid)).to eq([7, 4])
      end

      it "no path has step uid 8" do
        result = described_class.infer_for(app: app, user: user)
        no_path = result.paths.find { |p| p[:title] == "no" }
        expect(no_path[:steps].pluck(:step_uid)).to eq([8])
      end
    end

    context "with Lead without email and share_typical_time off" do
      let(:user) { app.add_lead({}) }

      before do
        user.update!(lang: "en")
        settings = app.lead_tasks_settings.merge("share_typical_time" => false)
        app.update!(lead_tasks_settings: settings)
      end

      it "first path still includes route_support but no reply_soon step 1" do
        result = described_class.infer_for(app: app, user: user)
        uids = result.paths.first[:steps].pluck(:step_uid)
        expect(uids).not_to include(1)
        expect(uids).to include(5, 6)
      end
    end

    context "with Lead with email" do
      let(:user) { app.add_lead({ email: "lead@example.com" }) }

      before { user.update!(lang: "en") }

      it "first path does not include route_support steps" do
        result = described_class.infer_for(app: app, user: user)
        uids = result.paths.first[:steps].pluck(:step_uid)
        expect(uids).not_to include(5, 6)
      end

      it "yes path does not include email_requirement steps" do
        app.update!(email_requirement: "Always")
        result = described_class.infer_for(app: app, user: user)
        yes_path = result.paths.find { |p| p[:title] == "yes" }
        expect(yes_path[:steps].pluck(:step_uid)).to eq([7, 4])
      end
    end

    context "with routing close" do
      let(:user) { app.add_lead({}) }

      before do
        user.update!(lang: "en")
        settings = app.lead_tasks_settings.merge("routing" => "close")
        app.update!(lead_tasks_settings: settings)
      end

      it "first path follow_actions include close" do
        result = described_class.infer_for(app: app, user: user)
        actions = result.paths.first[:follow_actions]
        expect(actions).to include(hash_including(key: "close"))
      end
    end

    context "with routing assign" do
      let(:user) { app.add_lead({}) }
      let!(:assignee_agent) { app.add_agent({ email: "assignee@test.com", first_name: "Assignee" }).agent }

      before do
        user.update!(lang: "en")
        settings = app.lead_tasks_settings.merge("routing" => "assign", "assignee" => assignee_agent.id)
        app.update!(lead_tasks_settings: settings)
      end

      it "first path follow_actions include assign with assignee" do
        result = described_class.infer_for(app: app, user: user)
        actions = result.paths.first[:follow_actions]
        expect(actions).to include(hash_including(key: "assign"))
      end

      it "first path follow_actions is empty when assignee is blank" do
        settings = app.lead_tasks_settings.merge("routing" => "assign", "assignee" => nil)
        app.update!(lead_tasks_settings: settings)
        result = described_class.infer_for(app: app, user: user)
        expect(result.paths.first[:follow_actions]).to be_empty
      end
    end

    context "with Visitor" do
      let(:user) { app.add_anonymous_user({}) }

      before { user.update!(lang: "en") }

      it "first path includes route_support steps 5 and 6" do
        result = described_class.infer_for(app: app, user: user)
        uids = result.paths.first[:steps].pluck(:step_uid)
        expect(uids).to include(5, 6)
      end
    end
  end

  describe ".find_factory_template" do
    let(:user) { app.add_user(email: "user@example.com") }

    before { user.update!(lang: "en") }

    it "returns an infer template for trigger infer" do
      result = described_class.find_factory_template(app: app, app_user: user, data: { "trigger" => "infer" })
      expect(result.id).to eq("infer")
    end

    it "returns a request_for_email template" do
      result = described_class.find_factory_template(app: app, app_user: user, data: { "trigger" => "request_for_email" })
      expect(result.id).to eq("request_for_email")
    end

    it "returns a route_support template" do
      result = described_class.find_factory_template(app: app, app_user: user, data: { "trigger" => "route_support" })
      expect(result.id).to eq("route_support")
    end

    it "propagates the typical_reply_time interpolation error" do
      expect do
        described_class.find_factory_template(app: app, app_user: user, data: { "trigger" => "typical_reply_time" })
      end.to raise_error(ArgumentError, /wrong number of arguments/)
    end

    it "raises for unknown trigger" do
      expect do
        described_class.find_factory_template(app: app, app_user: user, data: { "trigger" => "unknown" })
      end.to raise_error(RuntimeError, "trigger template not found")
    end
  end

  describe ".find_task" do
    let(:user) { app.add_lead({}) }

    before { user.update!(lang: "en") }

    it "returns a factory template when bot_tasks.find fails" do
      trigger, path = described_class.find_task(
        data: { "trigger" => "infer", "step" => "8" },
        app: app,
        app_user: user
      )
      expect(trigger.id).to eq("infer")
      expect(path["title"]).to eq("no")
    end

    it "returns a saved bot_task when it exists" do
      bot_task = app.bot_tasks.create!(name: "Custom bot")
      trigger, _path = described_class.find_task(
        data: { "trigger" => bot_task.id.to_s, "step" => "1" },
        app: app,
        app_user: user
      )
      expect(trigger).to eq(bot_task)
    end

    it "returns nil path when no step matches" do
      _trigger, path = described_class.find_task(
        data: { "trigger" => "infer", "step" => "999" },
        app: app,
        app_user: user
      )
      expect(path).to be_nil
    end
  end

  describe "DSL methods" do
    subject { described_class.new }

    it "path appends to paths array" do
      agent = double("agent", name: "A", email: "a@b.com", id: 1)
      subject.path(title: "test", steps: [subject.message(text: "hi", uuid: 1, agent: agent)])
      expect(subject.paths.size).to eq(1)
      expect(subject.paths.first[:title]).to eq("test")
    end

    it "message builds a step with step_uid and messages" do
      agent = double("agent", name: "A", email: "a@b.com", id: 1)
      step = subject.message(text: "hello", uuid: 42, agent: agent)
      expect(step[:step_uid]).to eq(42)
      expect(step[:messages].first[:html_content]).to eq("hello")
      expect(step[:messages].first[:app_user][:display_name]).to eq("A")
    end

    it "controls builds a step with controls hash" do
      step = subject.controls(uuid: 5, type: "data_retrieval", schema: [{ id: "email" }])
      expect(step[:step_uid]).to eq(5)
      expect(step[:controls][:type]).to eq("data_retrieval")
      expect(step[:controls][:schema]).to eq([{ id: "email" }])
    end

    it "button builds a button element" do
      btn = subject.button(label: "yes", next_uuid: 3)
      expect(btn[:element]).to eq("button")
      expect(btn[:label]).to eq("yes")
      expect(btn[:next_step_uuid]).to eq(3)
    end

    it "input builds an input element" do
      inp = subject.input(label: "Email", name: "email", placeholder: "enter email")
      expect(inp[:element]).to eq("input")
      expect(inp[:name]).to eq("email")
      expect(inp[:label]).to eq("Email")
      expect(inp[:placeholder]).to eq("enter email")
    end

    it "assign builds an assign action" do
      action = subject.assign(42)
      expect(action[:key]).to eq("assign")
      expect(action[:value]).to eq(42)
    end

    it "close builds a close action" do
      action = subject.close
      expect(action[:key]).to eq("close")
    end

    it "config yields self" do
      yielded = nil
      subject.config { |c| yielded = c }
      expect(yielded).to eq(subject)
    end
  end
end
