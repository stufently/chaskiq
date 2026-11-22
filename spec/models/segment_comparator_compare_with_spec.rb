# frozen_string_literal: true

require "rails_helper"

RSpec.describe SegmentComparator, "#compare_with" do
  subject(:comparator) { described_class.new(user: nil, predicates: []) }

  # --- contains_start ---
  it { expect(comparator.compare_with("hello world", "hello", "contains_start")).to eq(true) }
  it { expect(comparator.compare_with("hello world", "world", "contains_start")).to eq(false) }

  # --- contains_ends ---
  it { expect(comparator.compare_with("hello world", "world", "contains_ends")).to eq(true) }
  it { expect(comparator.compare_with("hello world", "hello", "contains_ends")).to eq(false) }

  # --- is_null ---
  it { expect(comparator.compare_with("", nil, "is_null")).to eq(true) }
  it { expect(comparator.compare_with(nil, nil, "is_null")).to eq(true) }
  it { expect(comparator.compare_with("a", nil, "is_null")).to eq(false) }

  # --- is_not_null ---
  it { expect(comparator.compare_with("a", nil, "is_not_null")).to eq(true) }
  it { expect(comparator.compare_with("", nil, "is_not_null")).to eq(false) }
  it { expect(comparator.compare_with(nil, nil, "is_not_null")).to eq(false) }

  # --- contains ---
  it { expect(comparator.compare_with("abcdef", "bcd", "contains")).to eq(true) }
  it { expect(comparator.compare_with("abcdef", "xyz", "contains")).to eq(false) }

  # --- not_contains ---
  it { expect(comparator.compare_with("abcdef", "xyz", "not_contains")).to eq(true) }
  it { expect(comparator.compare_with("abcdef", "bcd", "not_contains")).to eq(false) }

  # --- not_eq ---
  it { expect(comparator.compare_with("a", "b", "not_eq")).to eq(true) }
  it { expect(comparator.compare_with("a", "a", "not_eq")).to eq(false) }

  # --- eq ---
  it { expect(comparator.compare_with("a", "a", "eq")).to eq(true) }
  it { expect(comparator.compare_with("a", "b", "eq")).to eq(false) }
  it { expect(comparator.compare_with(2, 2, "eq")).to eq(true) }

  # --- lt ---
  it { expect(comparator.compare_with(1, 2, "lt")).to eq(true) }
  it { expect(comparator.compare_with(2, 2, "lt")).to eq(false) }
  it { expect(comparator.compare_with(3, 2, "lt")).to eq(false) }

  # --- lteq ---
  it { expect(comparator.compare_with(1, 2, "lteq")).to eq(true) }
  it { expect(comparator.compare_with(2, 2, "lteq")).to eq(true) }
  it { expect(comparator.compare_with(3, 2, "lteq")).to eq(false) }

  # --- gt ---
  it { expect(comparator.compare_with(3, 2, "gt")).to eq(true) }
  it { expect(comparator.compare_with(2, 2, "gt")).to eq(false) }
  it { expect(comparator.compare_with(1, 2, "gt")).to eq(false) }

  # --- gteq ---
  it { expect(comparator.compare_with(3, 2, "gteq")).to eq(true) }
  it { expect(comparator.compare_with(2, 2, "gteq")).to eq(true) }
  it { expect(comparator.compare_with(1, 2, "gteq")).to eq(false) }

  # --- in ---
  it { expect(comparator.compare_with("b", %w[a b c], "in")).to eq(true) }
  it { expect(comparator.compare_with("z", %w[a b c], "in")).to eq(false) }

  # --- argument order matters ---
  it { expect(comparator.compare_with("abc", "abcd", "contains")).to eq(false) }
  it { expect(comparator.compare_with("b", "a", "lt")).to eq(false) }

  # --- unknown / nil / symbol comparison → nil ---
  it { expect(comparator.compare_with("a", "a", "between")).to be_nil }
  it { expect(comparator.compare_with("a", "a", nil)).to be_nil }
  it { expect(comparator.compare_with("a", "a", :eq)).to be_nil }

  # --- nil user_input with ordering / string methods → NoMethodError ---
  it { expect { comparator.compare_with(nil, 1, "lt") }.to raise_error(NoMethodError) }
  it { expect { comparator.compare_with(nil, "x", "contains_start") }.to raise_error(NoMethodError) }

  # --- integration via compare? ---
  it "checks predicate via compare? with contains_ends" do
    app = FactoryBot.create(:app)
    user = app.add_user(email: "user@example.com")
    predicates = [
      { "attribute" => "email", "comparison" => "contains_ends", "type" => "string", "value" => "example.com" },
      { "type" => "match", "value" => "and" }
    ]
    comparator = described_class.new(user: user, predicates: predicates)
    expect(comparator.compare?).to eq(true)
  end

  it "checks predicate via compare? with not_contains" do
    app = FactoryBot.create(:app)
    user = app.add_user(email: "user@example.com")
    predicates = [
      { "attribute" => "email", "comparison" => "not_contains", "type" => "string", "value" => "example.com" },
      { "type" => "match", "value" => "and" }
    ]
    comparator = described_class.new(user: user, predicates: predicates)
    expect(comparator.compare?).to eq(false)
  end
end
