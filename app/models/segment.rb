# frozen_string_literal: true

require "chronic"

class Segment < ApplicationRecord
  include UnionScope

  belongs_to :app, optional: true
  store :properties, accessors: %i[
    per_page
    predicates
    sort_by
    sort_direction
  ], coder: JSON

  validate :check_array

  def check_array
    return if predicates.blank?

    add_errors_on_predicates
  end

  def add_errors_on_predicates
    predicates.each do |prop|
      attrs = %i[attribute comparison type value].map(&:to_s)
      next unless (prop.keys - attrs).any?

      handle_predicate_error(prop)
    end
  end

  def handle_predicate_error(prop)
    errors.add(:properties, "predicates are invalid") if prop["type"] != "or"
  end

  # predicate example:
  # {type: "role", attribute: "role", comparison: "eq", value: "user_role"}

  def query
    app
    AppUser.arel_table
    app.app_users.arel_table[Arel.star]
  end

  def execute_query
    AppUser.arel_table
    AppUser.arel_table
    query_builder
  end

  def cast_int(field)
    Arel::Nodes::NamedFunction.new("cast", [field.as("int")])
  end

  def cast_date(field)
    Arel::Nodes::NamedFunction.new("cast", [field.as("date")])
  end

  def predicates_for_arel
    predicates.reject { |o| o["attribute"] == "tags" }
  end

  # JSONB queries on steroids
  # https://jes.al/2016/01/querying-json-fields-in-postgresql-using-activerecord/

  def query_builder
    Arel::Table.new :tags # Base Rel-var
    query = nil
    nil
    Array(predicates_for_arel).each_with_index do |predicate, _index|
      next if predicate["type"] == "match"

      # check if its in table column
      field = build_predicate_field(predicate)

      check = check_predicate(predicate, field)

      query = build_query(check, query)
    end
    tagged_result(query)
  end

  def build_query(check, query)
    if query.nil?
      check
    elsif predicates.find { |o| o["type"] == "match" && o["value"] == "or" }
      query.or(check)
    else
      query.and(check)
    end
  end

  def check_predicate(predicate, field)
    # date predicates
    case predicate["type"]
    when "date"
      cast_date(field).send(predicate["comparison"], Chronic.parse(predicate["value"]))
    when "string"
      check_string(predicate, field)
    when "integer"
      check_integer(predicate, field)
    end
  end

  def check_integer(predicate, field)
    case predicate["comparison"]
    when "is_null"
      cast_int(field).eq(nil)
    when "is_not_null"
      cast_int(field).not_eq(nil)
    else
      if %w[eq lt lteq gt gteq].include?(predicate["comparison"])
        cast_int(field).send(
          predicate["comparison"],
          predicate["value"]
        )
      end
    end
  end

  def check_string(predicate, field)
    case predicate["comparison"]
    when "contains_start"
      query_string = "#{predicate['value']}%"
      field.matches(query_string)
    when "contains_ends"
      query_string = "%#{predicate['value']}"
      field.matches(query_string)
    when "is_null"
      field.eq(nil)
    when "is_not_null"
      field.not_eq(nil)
    when "contains"
      query_string = "%#{predicate['value']}%"
      field.matches(query_string)
    when "not_contains"
      query_string = "%#{predicate['value']}%"
      field.does_not_match(query_string)
    else
      field.send(predicate["comparison"], predicate["value"])
    end
  end

  def build_predicate_field(predicate)
    arel_table = AppUser.arel_table
    cols = AppUser.columns
    if cols.map(&:name).include?(predicate["attribute"])
      arel_table[predicate["attribute"]]
    else
      # otherwise use in JSONB properties column
      Arel::Nodes::InfixOperation.new("->>",
                                      arel_table[:properties],
                                      Arel::Nodes.build_quoted(predicate["attribute"].to_s))
    end
  end

  def tagged_result(query)
    result = app.app_users
    tags = Arel::Table.new(:tags)
    field = tags[:name]
    or_predicate = predicates.find { |o| o["type"] == "match" && o["value"] == "or" }

    tags_query, to_exclude = accumulate_tag_state(result, tags, field, or_predicate)

    return apply_or_tags(result, Arel::Table.new(:taggings), tags_query, query) if or_predicate && tags_query

    result = apply_exclusions(result, to_exclude)
    return apply_tag_joins(result, tags_query, query) if tags_query
    return result.where(query) if query

    result
  end

  private

  def build_tag_check(predicate, tags, field)
    inverse = false
    check = case predicate["comparison"]
            when "contains_start"
              field.matches("#{predicate['value']}%")
            when "contains_ends"
              field.matches("%#{predicate['value']}")
            when "is_null"
              inverse = true
              tags[:id].not_eq(nil)
            when "is_not_null"
              tags[:id].not_eq(nil)
            when "contains"
              field.matches("%#{predicate['value']}%")
            when "not_contains"
              inverse = true
              field.matches("%#{predicate['value']}%")
            when "not_eq"
              inverse = true
              field.eq(predicate["value"].to_s)
            else
              field.send(predicate["comparison"], predicate["value"])
            end
    [check, inverse]
  end

  def accumulate_tag_state(result, tags, field, or_predicate)
    ctx = { tags_query: nil, to_exclude: [] }

    predicates.select { |o| o["attribute"] == "tags" }.each_with_index do |predicate, index|
      check, inverse = build_tag_check(predicate, tags, field)
      process_tag_predicate(result, tags, check, inverse, index, or_predicate, ctx)
    end

    [ctx[:tags_query], ctx[:to_exclude]]
  end

  def process_tag_predicate(result, tags, check, inverse, index, or_predicate, ctx)
    if or_predicate
      ctx[:tags_query] = ctx[:tags_query].blank? ? check : ctx[:tags_query].or(check)
      return
    end

    taggings = Arel::Table.new(:taggings).alias("tags_index_#{index}")
    init = ctx[:tags_query].nil? || inverse ? result.arel_table : ctx[:tags_query]
    j = build_tagging_join(result, taggings, tags, check, init)
    if inverse
      ctx[:to_exclude] << j
    else
      ctx[:tags_query] = j
    end
  end

  def build_tagging_join(result, taggings, tags, check, init)
    q = taggings[:tag_id].in(tags.project(tags[:id]).where(check))
    init.join(taggings).on(
      taggings[:taggable_id].eq(result.arel_table[:id]).and(
        taggings[:taggable_type].eq("AppUser")
      ).and(q)
    )
  end

  def apply_or_tags(result, base_taggings, tags_query, query)
    tags = Arel::Table.new(:tags)
    a = base_taggings[:taggable_id].eq(result.arel_table[:id]).and(
      base_taggings[:taggable_type].eq("AppUser")
    ).and(
      base_taggings[:tag_id].in(tags.project(tags[:id]).where(tags_query))
    )
    g = ActsAsTaggableOn::Tagging.arel_table
    b = g.project(Arel.star).where(a).exists
    query ? result.where(b).where(query) : result.where(b)
  end

  def apply_exclusions(result, to_exclude)
    exclusions = to_exclude.map do |tag_join|
      result.select("app_users.id").arel.except(
        result.joins(tag_join.join_sources).select("app_users.id").arel
      )
    end
    exclusions.reduce(result) do |relation, exclusion|
      relation.where(relation.arel_table[:id].in(exclusion))
    end
  end

  def apply_tag_joins(result, tags_query, query)
    joined = result.joins(tags_query.join_sources)
    joined = joined.where(query) if query
    joined.distinct
  end

  def es_search_attrs
    %w[
      id type name first_name last_name email lang tags phone
      last_visited_at referrer state ip city region country lat lng
      postal web_sessions timezone browser browser_version os os_version
      browser_language
    ]
  end

  def standard_comparison_fragment(pred)
    attr = pred["attribute"].to_s
    case pred["comparison"]
    when "in"
      terms_fragment(:filter, attr, pred["value"])
    when "eq", "not_eq"
      term_fragment(pred["comparison"] == "eq" ? :must : :must_not, attr, pred["value"])
    when "contains", "not_contains"
      clause = pred["comparison"] == "contains" ? :must : :must_not
      match_fragment(clause, "#{attr}.word_start", pred["value"])
    when "is_null", "is_not_null"
      clause = pred["comparison"] == "is_null" ? :must : :must_not
      exists_fragment(clause, attr, pred["value"])
    when "contains_ends"
      filter_regex_fragment(:filter, attr, ".*#{pred['value']}")
    when "contains_start"
      match_fragment(:filter, "#{attr}.word_start", pred["value"])
    end
  end

  def nested_comparison_fragment(pred)
    case pred["comparison"]
    when "eq"
      term_fragment(:must, "custom_attributes.value", pred["value"])
    when "not_eq"
      term_fragment(:must_not, "custom_attributes.value", pred["value"])
    when "contains"
      filter_regex_fragment(:filter, "custom_attributes.value", ".*#{pred['value']}.*")
    when "not_contains"
      filter_regex_fragment(:must_not, "custom_attributes.value", ".*#{pred['value']}.*")
    when "is_null"
      exists_fragment(:must, "custom_attributes.value", pred["value"])
    when "is_not_null"
      exists_fragment(:must_not, "custom_attributes.value", pred["value"])
    when "contains_ends"
      filter_regex_fragment(:filter, "custom_attributes.value", ".*#{pred['value']}")
    when "contains_start"
      filter_regex_fragment(:filter, "custom_attributes.value", "#{pred['value']}.*")
    end
  end

  def es_query_body(q_predicates, nested_preds)
    {
      track_total_hits: true,
      query: {
        bool: {
          must: (clause_group(q_predicates, :must) << nested_preds_group(:c, nested_preds)).compact.flatten,
          must_not: clause_group(q_predicates, :must_not),
          should: clause_group(q_predicates, :should),
          filter: clause_group(q_predicates, :filter)
        }
      }
    }
  end

  public

  def term_fragment(clause, attribute, value)
    {
      clause: clause,
      fragment: {
        term: { attribute => { value: value } }
      }
    }
  end

  def terms_fragment(clause, attribute, value)
    {
      clause: clause,
      fragment: {
        terms: { attribute => value }
      }
    }
  end

  def match_fragment(clause, attribute, value, analyzer = "searchkick_search")
    {
      clause: clause,
      fragment: {
        match: {
          attribute => {
            query: value,
            boost: 10,
            operator: "and",
            analyzer: analyzer
          }
        }
      }
    }
  end

  def filter_regex_fragment(clause, attribute, value)
    {
      clause: clause,
      fragment: {
        regexp: {
          attribute => {
            value: value,
            flags: "NONE",
            case_insensitive: true
          }
        }
      }
    }
  end

  def exists_fragment(clause, attribute, _value)
    {
      clause: clause,
      fragment: {
        bool: {
          must_not: {
            exists: {
              field: attribute
            }
          }
        }
      }
    }
  end

  def clause_group(predicates, clause)
    predicates&.filter { |o| o[:clause] == clause }&.pluck(:fragment)&.flatten || []
  end

  def nested_preds_group(_clause, attributes)
    return attributes if attributes.blank?

    q_predicates = attributes.map { |pred| nested_comparison_fragment(pred) }
                             &.flatten&.compact || []

    fields = attributes.map do |o|
      {
        term: { "custom_attributes.name" => o["attribute"] }
      }
    end

    {
      nested: {
        path: "custom_attributes",
        query: {
          bool: {
            must_not: clause_group(q_predicates, :must_not),
            should: clause_group(q_predicates, :should),
            filter: clause_group(q_predicates, :filter),
            must: fields + clause_group(q_predicates, :must)
          }
        }
      }
    }
  end

  def es_search(page = nil, per = nil)
    search_attrs = es_search_attrs
    custom_fields = app.custom_fields || []
    preds = predicates.filter do |o|
      o["type"] != "match" && search_attrs.include?(o["attribute"])
    end
    nested_preds = predicates.filter do |o|
      custom_fields.pluck("name").include?(o["attribute"])
    end

    q_predicates = preds.map { |pred| standard_comparison_fragment(pred) }
                        &.flatten&.compact || []
    q_predicates << { clause: :filter, fragment: { term: { app_id: { value: app_id } } } }

    query = es_query_body(q_predicates, nested_preds)
    Rails.logger.info(query)
    AppUser.search(body: query, page: page, per_page: per)
  end
end
