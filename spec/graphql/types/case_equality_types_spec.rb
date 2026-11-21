# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::MessengerType do
  let(:app) { FactoryBot.create(:app) }

  let(:inbound_settings) do
    { "users" => { "enabled" => true, "segment" => "all" }, "visitors" => { "enabled" => false } }
  end

  before { app.update!(inbound_settings: inbound_settings) }

  describe "#enabled_for_user" do
    context "when user is an AppUser" do
      let(:user) { app.add_user(email: "test@example.com") }

      it "returns true when users segment is enabled for all" do
        ctx = { set_locale: -> {}, get_app_user: -> { user } }
        instance = described_class.send(:new, app, ctx)
        expect(instance.enabled_for_user).to eq(true)
      end
    end

    context "when user is an anonymous visitor" do
      let(:user) { app.add_anonymous_user({}) }

      it "returns nil when visitors segment is disabled" do
        ctx = { set_locale: -> {}, get_app_user: -> { user } }
        instance = described_class.send(:new, app, ctx)
        expect(instance.enabled_for_user).to be_nil
      end
    end
  end
end

RSpec.describe Types::RoleType do
  let(:app) { FactoryBot.create(:app) }

  describe "#owner" do
    let(:agent_role) { app.add_agent({ email: "agent@example.com" }) }

    it "returns true when the role agent_id matches the app owner_id" do
      app.update!(owner_id: agent_role.agent_id)
      ctx = {}
      instance = described_class.send(:new, agent_role, ctx)
      expect(instance.owner).to eq(true)
    end

    it "returns false when the role agent_id does not match the app owner_id" do
      other_role = app.add_agent({ email: "other@example.com" })
      app.update!(owner_id: agent_role.agent_id)
      ctx = {}
      instance = described_class.send(:new, other_role, ctx)
      expect(instance.owner).to eq(false)
    end
  end
end
