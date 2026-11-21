# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::AppType, type: :graphql do
  let(:app) { FactoryBot.create(:app) }
  let(:agent) { app.add_agent({ email: "agent@test.cl", first_name: "Agent" }).agent }

  let(:context) { { current_user: agent } }
  let(:type_instance) { Types::AppType.send(:new, app, context) }

  before do
    app.update!(owner_id: agent.id)
    allow(type_instance).to receive(:authorize!).and_return(true)
    allow_any_instance_of(Plan).to receive(:allow_feature!).and_return(true)
  end

  describe "#app_packages" do
    it "returns enabled published packages ordered by id ascending" do
      pkg1 = AppPackage.new(name: "First", state: "enabled", published: true)
      pkg1.save!(validate: false)
      pkg2 = AppPackage.new(name: "Second", state: "enabled", published: true)
      pkg2.save!(validate: false)
      pkg3 = AppPackage.new(name: "Third", state: "enabled", published: true)
      pkg3.save!(validate: false)

      result = type_instance.app_packages
      ids = result.map(&:id)
      # Check that all created packages are present and in order
      expect(ids).to include(pkg1.id, pkg2.id, pkg3.id)
      expect(ids.index(pkg1.id)).to be < ids.index(pkg2.id)
      expect(ids.index(pkg2.id)).to be < ids.index(pkg3.id)
    end
  end

  describe "#segments" do
    it "returns segments ordered by id ascending, including global segments" do
      seg1 = app.segments.create!(predicates: [])
      seg2 = app.segments.create!(predicates: [])
      # Global segment (app_id: nil) should be included
      global_seg = Segment.create!(predicates: [], app_id: nil)
      # Segment from another app should NOT be included
      other_app = FactoryBot.create(:app)
      other_seg = other_app.segments.create!(predicates: [])

      result = type_instance.segments
      ids = result.map(&:id)
      expect(ids).to include(seg1.id, seg2.id, global_seg.id)
      expect(ids).not_to include(other_seg.id)
      expect(ids).to eq(ids.sort)
    end
  end

  describe "#assignment_rules" do
    it "returns assignment rules ordered by priority ascending via default_scope" do
      app.assignment_rules.create!(title: "Rule 1", agent: agent, priority: 2, conditions: [])
      app.assignment_rules.create!(title: "Rule 2", agent: agent, priority: 1, conditions: [])

      # Test both via GraphQL resolver and directly via model (default_scope)
      result = type_instance.assignment_rules
      priorities = result.map(&:priority)
      expect(priorities).to eq(%w[1 2].map(&:to_i))

      # Also verify default_scope works directly
      direct_result = app.assignment_rules.to_a
      direct_priorities = direct_result.map(&:priority)
      expect(direct_priorities).to eq(%w[1 2].map(&:to_i))
    end
  end

  describe "#collections" do
    it "returns article collections ordered by position ascending, not id" do
      # Create collections — acts_as_list assigns positions 1, 2
      app.article_collections.create!(title: "first")
      app.article_collections.create!(title: "second")

      # Reverse positions so order by position differs from order by id
      collections = app.article_collections.order(:id).to_a
      collections[0].update_column(:position, 2)
      collections[1].update_column(:position, 1)

      result = type_instance.collections(lang: "en")
      titles = result.map(&:title)
      # Should be ordered by position (reversed), not by id
      expect(titles).to eq(%w[second first])

      # Also verify positions are used for ordering
      positions = result.map(&:position)
      expect(positions).to eq(positions.sort)
    end
  end
end
