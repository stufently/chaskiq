# frozen_string_literal: true

require "rails_helper"

RSpec.describe Segment, type: :model do
  let(:app) { FactoryBot.create(:app) }
  let(:segment) { app.segments.create(predicates: []) }

  describe "#clause_group" do
    it "collects and flattens fragments for matching clause" do
      predicates = [
        { clause: 1, fragment: [1] },
        { clause: 1, fragment: [2, 3] },
        { clause: 2, fragment: [99] },
        { clause: 1, fragment: [4] }
      ]
      result = segment.send(:clause_group, predicates, 1)
      expect(result).to eq([1, 2, 3, 4])
    end

    it "returns empty array for nil predicates" do
      result = segment.send(:clause_group, nil, 1)
      expect(result).to eq([])
    end
  end
end
