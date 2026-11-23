# frozen_string_literal: true

require "rails_helper"

RSpec.describe Segment, "#es_search", type: :model do
  let!(:app) do
    FactoryBot.create(:app, custom_fields: [
                        { "name" => "plan", "type" => "string" },
                        { "name" => "age", "type" => "integer" }
                      ])
  end
  let(:captured) { {} }

  before do
    allow(AppUser).to receive(:search) do |**kwargs|
      captured[:body] = kwargs[:body]
      captured[:page] = kwargs[:page]
      captured[:per_page] = kwargs[:per_page]
      double("Searchkick::Relation", records: AppUser.none)
    end
    allow(Rails).to receive_message_chain(:logger, :info)
  end

  def make_segment(preds)
    app.segments.create(predicates: preds)
  end

  def run_es(segment, page = nil, per = nil)
    segment.es_search(page, per)
    captured[:body]
  end

  def bool(body)
    body.dig(:query, :bool)
  end

  describe "public signature" do
    it "accepts optional page and per_page" do
      seg = make_segment([])
      expect { seg.es_search }.not_to raise_error
      expect { seg.es_search(1) }.not_to raise_error
      expect { seg.es_search(1, 20) }.not_to raise_error
    end

    it "passes page and per_page to AppUser.search" do
      seg = make_segment([])
      run_es(seg, 2, 15)
      expect(captured[:page]).to eq(2)
      expect(captured[:per_page]).to eq(15)
    end

    it "passes nil page and per_page when omitted" do
      seg = make_segment([])
      run_es(seg)
      expect(captured[:page]).to be_nil
      expect(captured[:per_page]).to be_nil
    end
  end

  describe "app_id filter" do
    it "always includes app_id in filter clause" do
      seg = make_segment([])
      body = run_es(seg)
      filters = bool(body)[:filter]
      app_id_filter = filters.find { |f| f.dig(:term, :app_id, :value) == app.id }
      expect(app_id_filter).to be_present
    end
  end

  describe "empty predicates" do
    it "produces a valid query with only app_id filter" do
      seg = make_segment([])
      body = run_es(seg)
      expect(body[:track_total_hits]).to eq(true)
      expect(bool(body)[:must]).to eq([])
      expect(bool(body)[:must_not]).to eq([])
      expect(bool(body)[:should]).to eq([])
      filters = bool(body)[:filter]
      expect(filters.size).to eq(1)
      expect(filters.first.dig(:term, :app_id, :value)).to eq(app.id)
    end
  end

  describe "match-type predicates are skipped" do
    it "skips match predicates on searchable standard fields" do
      seg = make_segment([
                           { "type" => "match", "attribute" => "name", "comparison" => "eq", "value" => "excluded" }
                         ])
      body = run_es(seg)
      expect(bool(body)).to eq(
        must: [], must_not: [], should: [], filter: [{ term: { app_id: { value: app.id } } }]
      )
    end
  end

  describe "unknown attributes are skipped" do
    it "ignores attributes not in search_attrs and not in custom_fields" do
      seg = make_segment([
                           { "type" => "string", "attribute" => "unknown_field", "comparison" => "eq", "value" => "x" }
                         ])
      body = run_es(seg)
      expect(bool(body)[:must]).to eq([])
    end
  end

  describe "standard field comparisons" do
    it "eq produces must term" do
      seg = make_segment([
                           { "type" => "string", "attribute" => "email", "comparison" => "eq", "value" => "foo@bar.com" }
                         ])
      body = run_es(seg)
      must = bool(body)[:must]
      expect(must).to include({ term: { "email" => { value: "foo@bar.com" } } })
    end

    it "not_eq produces must_not term" do
      seg = make_segment([
                           { "type" => "string", "attribute" => "email", "comparison" => "not_eq", "value" => "foo@bar.com" }
                         ])
      body = run_es(seg)
      must_not = bool(body)[:must_not]
      expect(must_not).to include({ term: { "email" => { value: "foo@bar.com" } } })
    end

    it "in produces filter terms" do
      seg = make_segment([
                           { "type" => "string", "attribute" => "state", "comparison" => "in", "value" => %w[online offline] }
                         ])
      body = run_es(seg)
      filters = bool(body)[:filter]
      expect(filters).to include({ terms: { "state" => %w[online offline] } })
    end

    it "contains produces must match on word_start" do
      seg = make_segment([
                           { "type" => "string", "attribute" => "name", "comparison" => "contains", "value" => "john" }
                         ])
      body = run_es(seg)
      must = bool(body)[:must]
      expect(must).to include(
        match: { "name.word_start" => { query: "john", boost: 10, operator: "and", analyzer: "searchkick_search" } }
      )
    end

    it "not_contains produces must_not match on word_start" do
      seg = make_segment([
                           { "type" => "string", "attribute" => "name", "comparison" => "not_contains", "value" => "spam" }
                         ])
      body = run_es(seg)
      must_not = bool(body)[:must_not]
      expect(must_not).to include(
        match: { "name.word_start" => { query: "spam", boost: 10, operator: "and", analyzer: "searchkick_search" } }
      )
    end

    it "is_null produces must exists negation" do
      seg = make_segment([
                           { "type" => "string", "attribute" => "phone", "comparison" => "is_null", "value" => nil }
                         ])
      body = run_es(seg)
      must = bool(body)[:must]
      expect(must).to include(bool: { must_not: { exists: { field: "phone" } } })
    end

    it "is_not_null produces must_not exists negation" do
      seg = make_segment([
                           { "type" => "string", "attribute" => "phone", "comparison" => "is_not_null", "value" => nil }
                         ])
      body = run_es(seg)
      must_not = bool(body)[:must_not]
      expect(must_not).to include(bool: { must_not: { exists: { field: "phone" } } })
    end

    it "contains_ends produces filter regexp with suffix pattern" do
      seg = make_segment([
                           { "type" => "string", "attribute" => "email", "comparison" => "contains_ends", "value" => "@gmail.com" }
                         ])
      body = run_es(seg)
      filters = bool(body)[:filter]
      expect(filters).to include(
        regexp: { "email" => { value: ".*@gmail.com", flags: "NONE", case_insensitive: true } }
      )
    end

    it "contains_start produces filter match on word_start" do
      seg = make_segment([
                           { "type" => "string", "attribute" => "email", "comparison" => "contains_start", "value" => "admin" }
                         ])
      body = run_es(seg)
      filters = bool(body)[:filter]
      expect(filters).to include(
        match: { "email.word_start" => { query: "admin", boost: 10, operator: "and", analyzer: "searchkick_search" } }
      )
    end
  end

  describe "nested custom field comparisons" do
    it "eq produces nested must term on custom_attributes" do
      seg = make_segment([
                           { "type" => "string", "attribute" => "plan", "comparison" => "eq", "value" => "premium" }
                         ])
      body = run_es(seg)
      must = bool(body)[:must]
      nested = must.find { |m| m.is_a?(Hash) && m[:nested] }
      expect(nested).to be_present
      expect(nested[:nested][:path]).to eq("custom_attributes")
      nested_must = nested[:nested][:query][:bool][:must]
      expect(nested_must).to include({ term: { "custom_attributes.name" => "plan" } })
      expect(nested_must).to include({ term: { "custom_attributes.value" => { value: "premium" } } })
    end

    it "not_eq produces nested must_not term" do
      seg = make_segment([
                           { "type" => "string", "attribute" => "plan", "comparison" => "not_eq", "value" => "free" }
                         ])
      body = run_es(seg)
      must = bool(body)[:must]
      nested = must.find { |m| m.is_a?(Hash) && m[:nested] }
      nested_must_not = nested[:nested][:query][:bool][:must_not]
      expect(nested_must_not).to include({ term: { "custom_attributes.value" => { value: "free" } } })
    end

    it "contains produces nested filter regexp" do
      seg = make_segment([
                           { "type" => "string", "attribute" => "plan", "comparison" => "contains", "value" => "prem" }
                         ])
      body = run_es(seg)
      must = bool(body)[:must]
      nested = must.find { |m| m.is_a?(Hash) && m[:nested] }
      nested_filter = nested[:nested][:query][:bool][:filter]
      expect(nested_filter).to include(
        regexp: { "custom_attributes.value" => { value: ".*prem.*", flags: "NONE", case_insensitive: true } }
      )
    end

    it "not_contains produces nested must_not regexp" do
      seg = make_segment([
                           { "type" => "string", "attribute" => "plan", "comparison" => "not_contains", "value" => "basic" }
                         ])
      body = run_es(seg)
      must = bool(body)[:must]
      nested = must.find { |m| m.is_a?(Hash) && m[:nested] }
      nested_must_not = nested[:nested][:query][:bool][:must_not]
      expect(nested_must_not).to include(
        regexp: { "custom_attributes.value" => { value: ".*basic.*", flags: "NONE", case_insensitive: true } }
      )
    end

    it "is_null produces nested must exists negation" do
      seg = make_segment([
                           { "type" => "string", "attribute" => "plan", "comparison" => "is_null", "value" => nil }
                         ])
      body = run_es(seg)
      must = bool(body)[:must]
      nested = must.find { |m| m.is_a?(Hash) && m[:nested] }
      nested_must = nested[:nested][:query][:bool][:must]
      expect(nested_must).to include(
        bool: { must_not: { exists: { field: "custom_attributes.value" } } }
      )
    end

    it "is_not_null produces nested must_not exists negation" do
      seg = make_segment([
                           { "type" => "string", "attribute" => "plan", "comparison" => "is_not_null", "value" => nil }
                         ])
      body = run_es(seg)
      must = bool(body)[:must]
      nested = must.find { |m| m.is_a?(Hash) && m[:nested] }
      nested_must_not = nested[:nested][:query][:bool][:must_not]
      expect(nested_must_not).to include(
        bool: { must_not: { exists: { field: "custom_attributes.value" } } }
      )
    end

    it "contains_ends produces nested filter regexp with suffix" do
      seg = make_segment([
                           { "type" => "string", "attribute" => "plan", "comparison" => "contains_ends", "value" => "ium" }
                         ])
      body = run_es(seg)
      must = bool(body)[:must]
      nested = must.find { |m| m.is_a?(Hash) && m[:nested] }
      nested_filter = nested[:nested][:query][:bool][:filter]
      expect(nested_filter).to include(
        regexp: { "custom_attributes.value" => { value: ".*ium", flags: "NONE", case_insensitive: true } }
      )
    end

    it "contains_start produces nested filter regexp with prefix" do
      seg = make_segment([
                           { "type" => "string", "attribute" => "plan", "comparison" => "contains_start", "value" => "pre" }
                         ])
      body = run_es(seg)
      must = bool(body)[:must]
      nested = must.find { |m| m.is_a?(Hash) && m[:nested] }
      nested_filter = nested[:nested][:query][:bool][:filter]
      expect(nested_filter).to include(
        regexp: { "custom_attributes.value" => { value: "pre.*", flags: "NONE", case_insensitive: true } }
      )
    end
  end

  describe "multiple predicates" do
    it "keeps predicate order and names of custom fields with unsupported comparisons" do
      seg = make_segment([
                           { "type" => "string", "attribute" => "email", "comparison" => "eq", "value" => "first@example.com" },
                           { "type" => "string", "attribute" => "age", "comparison" => "in", "value" => [31, 32] },
                           { "type" => "string", "attribute" => "name", "comparison" => "eq", "value" => "Second" },
                           { "type" => "string", "attribute" => "plan", "comparison" => "unknown", "value" => "ignored" },
                           { "type" => "string", "attribute" => "state", "comparison" => "in", "value" => ["online"] }
                         ])
      body = run_es(seg)
      expect(bool(body)).to eq(
        must: [
          { term: { "email" => { value: "first@example.com" } } },
          { term: { "name" => { value: "Second" } } },
          { nested: { path: "custom_attributes", query: { bool: {
            must_not: [], should: [], filter: [], must: [
              { term: { "custom_attributes.name" => "age" } },
              { term: { "custom_attributes.name" => "plan" } }
            ]
          } } } }
        ],
        must_not: [],
        should: [],
        filter: [{ terms: { "state" => ["online"] } }, { term: { app_id: { value: app.id } } }]
      )
    end

    it "combines standard and custom field predicates" do
      seg = make_segment([
                           { "type" => "string", "attribute" => "email", "comparison" => "eq", "value" => "a@b.com" },
                           { "type" => "string", "attribute" => "plan", "comparison" => "eq", "value" => "premium" }
                         ])
      body = run_es(seg)
      must = bool(body)[:must]
      expect(must).to include({ term: { "email" => { value: "a@b.com" } } })
      nested = must.find { |m| m.is_a?(Hash) && m[:nested] }
      expect(nested).to be_present
    end
  end

  describe "Rails.logger" do
    it "logs the query before AppUser.search" do
      seg = make_segment([])
      logger = instance_double(Logger)
      allow(Rails).to receive(:logger).and_return(logger)
      expect(logger).to receive(:info).with(hash_including(:query)).ordered
      expect(AppUser).to receive(:search).with(hash_including(:body)).ordered.and_return(
        double("Searchkick::Relation", records: AppUser.none)
      )
      seg.es_search
    end
  end

  describe "track_total_hits" do
    it "sets track_total_hits to true" do
      seg = make_segment([])
      body = run_es(seg)
      expect(body[:track_total_hits]).to eq(true)
    end
  end
end
