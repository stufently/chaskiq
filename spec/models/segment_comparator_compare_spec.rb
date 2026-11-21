# frozen_string_literal: true

require "rails_helper"

RSpec.describe SegmentComparator do
  let(:app) { FactoryBot.create(:app) }
  let(:user) { app.add_user(email: "test@example.com") }

  describe "#compare" do
    context "and match, all predicates true" do
      let(:predicates) do
        [
          { "attribute" => "email", "comparison" => "eq", "type" => "string", "value" => "test@example.com" },
          { "type" => "match", "value" => "and" }
        ]
      end

      it "returns true" do
        comparator = described_class.new(user: user, predicates: predicates)
        expect(comparator.compare).to eq(true)
      end
    end

    context "and match, one predicate false" do
      let(:predicates) do
        [
          { "attribute" => "email", "comparison" => "eq", "type" => "string", "value" => "test@example.com" },
          { "attribute" => "email", "comparison" => "eq", "type" => "string", "value" => "wrong@example.com" },
          { "type" => "match", "value" => "and" }
        ]
      end

      it "returns false" do
        comparator = described_class.new(user: user, predicates: predicates)
        expect(comparator.compare).to eq(false)
      end
    end

    context "or match, one predicate true" do
      let(:predicates) do
        [
          { "attribute" => "email", "comparison" => "eq", "type" => "string", "value" => "test@example.com" },
          { "attribute" => "email", "comparison" => "eq", "type" => "string", "value" => "wrong@example.com" },
          { "type" => "match", "value" => "or" }
        ]
      end

      it "returns true" do
        comparator = described_class.new(user: user, predicates: predicates)
        expect(comparator.compare).to eq(true)
      end
    end

    context "only match predicate" do
      let(:predicates) do
        [
          { "type" => "match", "value" => "and" }
        ]
      end

      it "returns true when there are only match predicates" do
        comparator = described_class.new(user: user, predicates: predicates)
        expect(comparator.compare).to eq(true)
      end
    end
  end

  describe "renamed" do
    describe "#compare?" do
      context "and match, all predicates true" do
        let(:predicates) do
          [
            { "attribute" => "email", "comparison" => "eq", "type" => "string", "value" => "test@example.com" },
            { "type" => "match", "value" => "and" }
          ]
        end

        it "returns true" do
          comparator = described_class.new(user: user, predicates: predicates)
          expect(comparator.compare?).to eq(true)
        end
      end

      context "and match, one predicate false" do
        let(:predicates) do
          [
            { "attribute" => "email", "comparison" => "eq", "type" => "string", "value" => "test@example.com" },
            { "attribute" => "email", "comparison" => "eq", "type" => "string", "value" => "wrong@example.com" },
            { "type" => "match", "value" => "and" }
          ]
        end

        it "returns false" do
          comparator = described_class.new(user: user, predicates: predicates)
          expect(comparator.compare?).to eq(false)
        end
      end

      context "or match, one predicate true" do
        let(:predicates) do
          [
            { "attribute" => "email", "comparison" => "eq", "type" => "string", "value" => "test@example.com" },
            { "attribute" => "email", "comparison" => "eq", "type" => "string", "value" => "wrong@example.com" },
            { "type" => "match", "value" => "or" }
          ]
        end

        it "returns true" do
          comparator = described_class.new(user: user, predicates: predicates)
          expect(comparator.compare?).to eq(true)
        end
      end
    end
  end
end
