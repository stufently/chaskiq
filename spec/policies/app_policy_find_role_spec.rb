# frozen_string_literal: true

require "rails_helper"

RSpec.describe AppPolicy, "#find_role_by_resource" do
  let(:app) { FactoryBot.create(:app) }
  let(:owner_role) do
    role = app.add_agent({ email: "owner@example.com" })
    app.update!(owner_id: role.agent_id)
    role
  end
  let(:owner) { owner_role.agent }
  let(:member_role) { app.add_agent({ email: "member@example.com" }, role_attrs: { role: "admin" }) }
  let(:member) { member_role.agent }

  let(:other_app) { FactoryBot.create(:app) }
  let(:other_agent_role) { other_app.add_agent({ email: "other@example.com" }) }
  let(:other_agent) { other_agent_role.agent }

  let(:conversation) do
    double(app: app, is_a?: false, respond_to?: true)
  end

  def policy(record, user:, **params)
    described_class.new(record, user: user, **params)
  end

  # --- App record ---

  context "with an App record and the owner" do
    it "returns true and sets @owner" do
      p = policy(app, user: owner)
      expect(p.find_role_by_resource).to eq(true)
      expect(p.instance_variable_get(:@owner)).to eq(true)
      expect(p.instance_variable_get(:@role)).to be_nil
    end
  end

  context "with an App record and a member" do
    it "returns the role" do
      p = policy(app, user: member)
      result = p.find_role_by_resource
      expect(result).to be_a(Role)
      expect(result.agent_id).to eq(member.id)
    end

    it "does not search for the role again on second call" do
      p = policy(app, user: member)
      p.find_role_by_resource
      allow(app).to receive(:roles).and_raise("should not be called again")
      expect(p.find_role_by_resource).to be_a(Role)
    end
  end

  # --- Conversation record (responds_to :app) ---

  context "with a conversation and the owner" do
    it "returns true" do
      p = policy(conversation, user: owner)
      expect(p.find_role_by_resource).to eq(true)
    end
  end

  context "with a conversation and a member" do
    it "returns the role" do
      p = policy(conversation, user: member)
      result = p.find_role_by_resource
      expect(result).to be_a(Role)
    end
  end

  context "with a conversation and an agent from another app" do
    it "returns nil" do
      p = policy(conversation, user: other_agent)
      expect(p.find_role_by_resource).to be_nil
    end
  end

  # --- nil / Object.new with app: param ---

  context "with nil record and app: param" do
    it "returns true for the owner" do
      p = policy(nil, user: owner, app: app)
      expect(p.find_role_by_resource).to eq(true)
    end

    it "returns the role for a member" do
      p = policy(nil, user: member, app: app)
      result = p.find_role_by_resource
      expect(result).to be_a(Role)
    end

    it "returns nil for an agent from another app" do
      p = policy(nil, user: other_agent, app: app)
      expect(p.find_role_by_resource).to be_nil
    end
  end

  context "with Object.new record and app: param" do
    let(:plain_object) { Object.new }

    it "returns true for the owner" do
      p = policy(plain_object, user: owner, app: app)
      expect(p.find_role_by_resource).to eq(true)
    end

    it "returns the role for a member" do
      p = policy(plain_object, user: member, app: app)
      result = p.find_role_by_resource
      expect(result).to be_a(Role)
    end

    it "returns nil for an agent from another app" do
      p = policy(plain_object, user: other_agent, app: app)
      expect(p.find_role_by_resource).to be_nil
    end
  end

  # --- record with app takes precedence over app: param ---

  context "when record has app and app: param is also given" do
    it "uses the record's app (owner of record's app wins)" do
      p = policy(conversation, user: owner, app: other_app)
      expect(p.find_role_by_resource).to eq(true)
    end

    it "uses the record's app (member of record's app gets role)" do
      p = policy(conversation, user: member, app: other_app)
      result = p.find_role_by_resource
      expect(result).to be_a(Role)
      expect(result.agent_id).to eq(member.id)
    end
  end

  # --- no record and no app: ---

  context "with no record and no app:" do
    it "returns nil and both ivars are nil" do
      p = policy(nil, user: owner)
      expect(p.find_role_by_resource).to be_nil
      expect(p.instance_variable_get(:@owner)).to be_nil
      expect(p.instance_variable_get(:@role)).to be_nil
    end
  end

  # --- record whose app is nil ---

  context "with a record whose app is nil and app: param given" do
    it "raises NoMethodError" do
      record = double(app: nil)
      p = policy(record, user: owner, app: app)
      expect { p.find_role_by_resource }.to raise_error(NoMethodError)
    end
  end
end
