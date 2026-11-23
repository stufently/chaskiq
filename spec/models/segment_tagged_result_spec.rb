# frozen_string_literal: true

require "rails_helper"

RSpec.describe Segment, "#tagged_result", type: :model do
  let!(:app) { FactoryBot.create(:app) }
  let!(:app2) { FactoryBot.create(:app) }

  def make_segment(preds)
    app.segments.create(predicates: preds)
  end

  def make_user(email, tags: [], app_ref: app)
    user = app_ref.add_visit(email: email)
    tags.each { |t| user.tag_list << t }
    user.save!
    user
  end

  describe "single tag predicates" do
    it "eq matches exact tag" do
      alice = make_user("alice@test.com", tags: %w[vip])
      bob = make_user("bob@test.com", tags: %w[regular])

      seg = make_segment([
                           { "attribute" => "tags", "comparison" => "eq", "type" => "string", "value" => "vip" }
                         ])
      result = seg.execute_query
      expect(result.pluck(:id)).to include(alice.id)
      expect(result.pluck(:id)).not_to include(bob.id)
    end

    it "not_eq excludes matching tag" do
      alice = make_user("alice_ne@test.com", tags: %w[vip])
      bob = make_user("bob_ne@test.com", tags: %w[regular])

      seg = make_segment([
                           { "attribute" => "tags", "comparison" => "not_eq", "type" => "string", "value" => "vip" }
                         ])
      result_ids = seg.execute_query.pluck(:id)
      expect(result_ids).not_to include(alice.id)
      expect(result_ids).to include(bob.id)
    end

    it "contains_start matches tag prefix" do
      alice = make_user("alice_cs@test.com", tags: %w[premium_user])
      make_user("bob_cs@test.com", tags: %w[basic_user])

      seg = make_segment([
                           { "attribute" => "tags", "comparison" => "contains_start", "type" => "string", "value" => "prem" }
                         ])
      result_ids = seg.execute_query.pluck(:id)
      expect(result_ids).to include(alice.id)
    end

    it "contains_ends matches tag suffix" do
      alice = make_user("alice_ce@test.com", tags: %w[gold_member])
      make_user("bob_ce@test.com", tags: %w[silver_member])

      seg = make_segment([
                           { "attribute" => "tags", "comparison" => "contains_ends", "type" => "string", "value" => "member" }
                         ])
      result_ids = seg.execute_query.pluck(:id)
      expect(result_ids).to include(alice.id)
    end

    it "contains matches tag substring" do
      alice = make_user("alice_c@test.com", tags: %w[beta_tester])
      make_user("bob_c@test.com", tags: %w[alpha_user])

      seg = make_segment([
                           { "attribute" => "tags", "comparison" => "contains", "type" => "string", "value" => "test" }
                         ])
      result_ids = seg.execute_query.pluck(:id)
      expect(result_ids).to include(alice.id)
    end

    it "not_contains excludes tag substring" do
      alice = make_user("alice_nc@test.com", tags: %w[beta_tester])
      bob = make_user("bob_nc@test.com", tags: %w[alpha_user])

      seg = make_segment([
                           { "attribute" => "tags", "comparison" => "not_contains", "type" => "string", "value" => "test" }
                         ])
      result_ids = seg.execute_query.pluck(:id)
      expect(result_ids).not_to include(alice.id)
      expect(result_ids).to include(bob.id)
    end

    it "is_null returns users without any tags" do
      alice = make_user("alice_null@test.com", tags: [])
      make_user("bob_null@test.com", tags: %w[has_tag])

      seg = make_segment([
                           { "attribute" => "tags", "comparison" => "is_null", "type" => "string", "value" => "" }
                         ])
      result_ids = seg.execute_query.pluck(:id)
      expect(result_ids).to include(alice.id)
    end

    it "is_not_null returns users with any tags" do
      make_user("alice_notnull@test.com", tags: [])
      bob = make_user("bob_notnull@test.com", tags: %w[has_tag])

      seg = make_segment([
                           { "attribute" => "tags", "comparison" => "is_not_null", "type" => "string", "value" => "" }
                         ])
      result_ids = seg.execute_query.pluck(:id)
      expect(result_ids).to include(bob.id)
    end
  end

  describe "multiple tags AND" do
    it "requires all tags when no OR predicate" do
      alice = make_user("alice_and@test.com", tags: %w[vip premium])
      bob = make_user("bob_and@test.com", tags: %w[vip])

      seg = make_segment([
                           { "attribute" => "tags", "comparison" => "eq", "type" => "string", "value" => "vip" },
                           { "attribute" => "tags", "comparison" => "eq", "type" => "string", "value" => "premium" }
                         ])
      result_ids = seg.execute_query.pluck(:id)
      expect(result_ids).to include(alice.id)
      expect(result_ids).not_to include(bob.id)
    end
  end

  it "builds independent EXCEPT subqueries for multiple exclusions" do
    included = make_user("eligible@test.com", tags: %w[regular])
    make_user("banned@test.com", tags: %w[banned])
    make_user("disabled@test.com", tags: %w[disabled])
    predicates = %w[banned disabled].map do |tag|
      { "attribute" => "tags", "comparison" => "not_eq", "type" => "string", "value" => tag }
    end

    result = make_segment(predicates).execute_query

    expect(result.to_sql.scan(/\bEXCEPT\b/).size).to eq(2)
    expect(result.pluck(:id)).to eq([included.id])
  end

  describe "multiple tags OR" do
    it "matches any tag with OR predicate" do
      alice = make_user("alice_or@test.com", tags: %w[vip])
      bob = make_user("bob_or@test.com", tags: %w[premium])
      make_user("charlie_or@test.com", tags: %w[regular])

      seg = make_segment([
                           { "type" => "match", "value" => "or", "attribute" => "match" },
                           { "attribute" => "tags", "comparison" => "eq", "type" => "string", "value" => "vip" },
                           { "attribute" => "tags", "comparison" => "eq", "type" => "string", "value" => "premium" }
                         ])
      result_ids = seg.execute_query.pluck(:id)
      expect(result_ids).to include(alice.id, bob.id)
    end

    it "OR with inverse predicate matches tag equality on BASE (inverse flag is local to AND path)" do
      alice = make_user("alice_or_inv@test.com", tags: %w[vip])
      make_user("bob_or_inv@test.com", tags: %w[regular])

      seg = make_segment([
                           { "type" => "match", "value" => "or", "attribute" => "match" },
                           { "attribute" => "tags", "comparison" => "not_eq", "type" => "string", "value" => "vip" }
                         ])
      result_ids = seg.execute_query.pluck(:id)
      expect(result_ids).to include(alice.id)
    end
  end

  describe "tag combined with regular filter" do
    it "AND: tag predicate plus string filter" do
      alice = make_user("alice_combo@test.com", tags: %w[vip])
      alice.update(email: "alice_combo@test.com")
      make_user("bob_combo@test.com", tags: %w[vip])

      seg = make_segment([
                           { "attribute" => "tags", "comparison" => "eq", "type" => "string", "value" => "vip" },
                           { "attribute" => "email", "comparison" => "eq", "type" => "string", "value" => "alice_combo@test.com" }
                         ])
      result_ids = seg.execute_query.pluck(:id)
      expect(result_ids).to include(alice.id)
    end

    it "OR: tag and non-tag predicates are ANDed on BASE (OR only applies within tag branch)" do
      alice = make_user("alice_or_combo@test.com", tags: %w[vip])
      bob = make_user("bob_or_combo@test.com", tags: %w[vip])

      seg = make_segment([
                           { "type" => "match", "value" => "or", "attribute" => "match" },
                           { "attribute" => "tags", "comparison" => "eq", "type" => "string", "value" => "vip" },
                           { "attribute" => "email", "comparison" => "eq", "type" => "string", "value" => "bob_or_combo@test.com" }
                         ])
      result_ids = seg.execute_query.pluck(:id)
      expect(result_ids).to include(bob.id)
      expect(result_ids).not_to include(alice.id)
    end
  end

  describe "scoping by app" do
    it "only returns users from the segment app" do
      alice = make_user("alice_scope@test.com", tags: %w[vip], app_ref: app)
      make_user("bob_scope@test.com", tags: %w[vip], app_ref: app2)

      seg = make_segment([
                           { "attribute" => "tags", "comparison" => "eq", "type" => "string", "value" => "vip" }
                         ])
      result_ids = seg.execute_query.pluck(:id)
      expect(result_ids).to include(alice.id)
      bob_app2 = AppUser.find_by(email: "bob_scope@test.com")
      expect(bob_app2).to be_present
      expect(result_ids).not_to include(bob_app2.id)
    end
  end

  describe "distinct results" do
    it "does not duplicate users with multiple matching tags" do
      alice = make_user("alice_dist@test.com", tags: %w[vip vip-plus])

      seg = make_segment([
                           { "attribute" => "tags", "comparison" => "contains", "type" => "string", "value" => "vip" }
                         ])
      result = seg.execute_query
      expect(result.count).to eq(1)
      expect(result.pluck(:id)).to eq([alice.id])
    end
  end

  describe "empty predicates" do
    it "returns all app users when no tag predicates" do
      alice = make_user("alice_empty@test.com", tags: %w[])
      bob = make_user("bob_empty@test.com", tags: %w[vip])

      seg = make_segment([])
      result_ids = seg.execute_query.pluck(:id)
      expect(result_ids).to include(alice.id, bob.id)
    end

    it "returns all users when only non-tag predicates" do
      alice = make_user("alice_nontag@test.com", tags: %w[])

      seg = make_segment([
                           { "attribute" => "email", "comparison" => "eq", "type" => "string", "value" => "alice_nontag@test.com" }
                         ])
      result_ids = seg.execute_query.pluck(:id)
      expect(result_ids).to include(alice.id)
    end
  end
end
