# frozen_string_literal: true

# Run with `bin/rails runner` (test env):
#   bin/rails runner docs/specs/fork-updates-r3b1-probes/r3b1_presence_guard.rb <r3b1_config.json>
#
# Rails/Blank rewrites `x.present?` as `!x.blank?` (`return unless x.present?` -> `return if x.blank?`)
# and Rails/Presence rewrites `x.m if x.present?` as `x.presence&.m`. Both are equal for x when x's
# class takes `present?` and `presence` from ActiveSupport/ActiveRecord, which define them as
# `!blank?` / `self if present?` (ActiveRecord::Core: present? true, blank? false). The receiver at
# each of the 9 sites is typed by reading the code ("sites" in r3b1_config.json: an ActiveRecord
# model or nil, a Mail::Message or nil, a GraphQL String argument, a JSON value); this guard checks
# those types after eager-loading the app with all its gems:
#   for every class C named in "classes" of a site, and every descendant of C:
#     C#presence is Object's (activesupport core_ext/object/blank.rb), and
#     C#present? is Object's or defined in activesupport core_ext/*/blank.rb or activerecord core.rb.
# Self-test first: a class with its own present? and one with its own presence must be reported.
# Prints "R3B1 GUARD PASS <n> classes" or "FAIL: ..." lines; exits 1 on any.
require "json"

Rails.application.eager_load!
puts "R3B1 EAGER LOAD OK"

AS_OBJECT = %r{/activesupport-[^/]+/lib/active_support/core_ext/object/blank\.rb\z}
AS_BLANK = %r{/activesupport-[^/]+/lib/active_support/core_ext/[a-z_]+/blank\.rb\z}
AR_CORE = %r{/activerecord-[^/]+/lib/active_record/core\.rb\z}

def file_of(klass, name) = klass.instance_method(name).source_location&.first.to_s

def violations(classes)
  classes.flat_map do |c|
    out = []
    out << "#{c}#presence comes from #{file_of(c, :presence)}" unless file_of(c, :presence).match?(AS_OBJECT)
    pf = file_of(c, :present?)
    out << "#{c}#present? comes from #{pf}" unless [AS_BLANK, AR_CORE].any? { |re| pf.match?(re) }
    out
  end
end

fails = []
own_present = Class.new { def present? = false }
own_presence = Class.new { def presence = self }
st = violations([own_present, own_presence])
fails << "self-test: own present? not reported" unless st.any? { |v| v.include?("#present?") }
fails << "self-test: own presence not reported" unless st.any? { |v| v.include?("#presence") }

cfg = JSON.parse(File.read(ARGV.fetch(0)))
fails << "r3b1_config.json has no typed sites" if cfg.fetch("sites").empty?
named = cfg["sites"].flat_map { |site| site.fetch("classes") }.uniq
classes = named.flat_map do |n|
  k = n.safe_constantize
  fails << "site class #{n} does not exist" unless k.is_a?(Class)
  k.is_a?(Class) ? [k] + k.descendants : []
end.uniq
fails.concat(violations(classes))
fails.each { |f| puts "FAIL: #{f}" }
exit 1 unless fails.empty?
puts "R3B1 GUARD PASS #{classes.size} classes"
