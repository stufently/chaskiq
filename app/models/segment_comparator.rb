# frozen_string_literal: true

class SegmentComparator
  # comparison name of a predicate => check of the user's value against the predicate's value
  COMPARISONS = {
    "contains_start" => ->(input, value) { input.start_with?(value) },
    "contains_ends" => ->(input, value) { input.end_with?(value) },
    "is_null" => ->(input, _value) { input.blank? },
    "is_not_null" => ->(input, _value) { input.present? },
    "contains" => ->(input, value) { input.include?(value) },
    "not_contains" => ->(input, value) { input.exclude?(value) },
    "not_eq" => ->(input, value) { input != value },
    "eq" => ->(input, value) { input == value },
    "lt" => ->(input, value) { input < value },
    "lteq" => ->(input, value) { input <= value },
    "gt" => ->(input, value) { input > value },
    "in" => ->(input, value) { input.in?(value) },
    "gteq" => ->(input, value) { input >= value }
  }.freeze

  attr_accessor :user, :predicates, :additional_fields

  def initialize(user:, predicates:, additional_fields: {})
    self.user = user
    self.predicates = predicates
    self.additional_fields = additional_fields
  end

  def compare?
    condition_predicates = predicates.reject { |o| o["type"] == "match" }

    query = handle_condition_predicates(condition_predicates)

    return true if query.empty?

    if predicates.find { |o| o["type"] == "match" && o["value"] == "or" }
      query.include?(true)
    else
      query.include?(true) && query.exclude?(false)
    end
  end
  alias compare compare?

  def handle_condition_predicates(condition_predicates)
    cols = AppUser.columns
    query = []
    condition_predicates.collect do |predicate|
      # predicate = predicate.with_indifferent_access
      # next if predicate['type'] == 'match'
      field = field_handler(cols, predicate)

      if field.is_a?(Array)
        field.each do |f|
          query << handle_comparison(f, predicate)
        end
      end

      query << handle_comparison(field, predicate)
    end
    query
  end

  def field_handler(cols, predicate)
    if additional_fields.key?(predicate["attribute"])
      additional_fields["message_content"]
    elsif cols.map(&:name).include?(predicate["attribute"])
      user.send(predicate["attribute"].to_sym)
    elsif predicate["attribute"] == "tags"
      user.tag_list
    elsif user.properties.key?(predicate["attribute"].to_s)
      user.properties[predicate["attribute"].to_s]
    end
  end

  def compare_with(user_input, predicate_value, comparison)
    COMPARISONS[comparison]&.call(user_input, predicate_value)
  end

  def handle_comparison(field, predicate)
    case predicate["type"]
    when "date"
      val = Chronic.parse(predicate["value"])
      field = Chronic.parse(field) if field.is_a?(String)
      check = compare_with(field, val, predicate["comparison"])
    # check = cast_date(field).send(predicate['comparison'], Chronic.parse(predicate['value']))
    when "string"
      check = compare_with(field.to_s, predicate["value"], predicate["comparison"])
    when "integer"
      check = compare_with(field.to_i, predicate["value"].to_i, predicate["comparison"])
    end
    check
  end
end
