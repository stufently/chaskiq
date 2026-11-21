# frozen_string_literal: true

class AssignmentRule < ApplicationRecord
  belongs_to :app
  belongs_to :agent
  store_accessor :conditions

  default_scope { order(:priority) }

  def check_rule_for(text, part)
    conditions.find { |o| o["type"] == "match" }
    query_conditions = conditions.reject { |o| o["type"] == "match" }

    # we will accept empty conditions as a true, ok ?
    return true if query_conditions.blank?

    SegmentComparator.new(
      user: part.authorable,
      predicates: conditions,
      additional_fields: { "message_content" => text }
    ).compare
  end
end
