# frozen_string_literal: true

# Run by r7d_boot.sh with `bin/rails runner` (RAILS_ENV=test, no CI variable: lazy loading) on a
# `git archive` copy. Writes JSON to ARGV[1]: for each moved constant of r7d_config.json ("moved":
# name => [file, host constant]) where Zeitwerk would autoload it from before anything is loaded
# (Object.autoload?), then - after Rails.application.eager_load! and Zeitwerk::Loader.eager_load_all -
# the public surface of the moved constants and their hosts: superclass, ancestors up to Object,
# public/private instance methods and singleton methods defined by the class itself, and whether it
# is an Active Record model or an Active Job (STI type columns and Sidekiq payloads name those).
require "json"

cfg = JSON.parse(File.read(ARGV.fetch(0)))
moved = cfg.fetch("moved")
autoload = moved.keys.to_h { |name| [name, Object.autoload?(name.to_sym)&.delete_prefix("#{Rails.root}/")] }
Rails.application.eager_load!
Zeitwerk::Loader.eager_load_all
names = (moved.keys + moved.values.map(&:last)).uniq.sort
surface = names.to_h do |name|
  c = Object.const_get(name)
  [name, {
    "superclass" => c.superclass&.name,
    "ancestors" => c.ancestors.take_while { |a| a != Object }.map { |a| a.name || "anon" },
    "public" => c.public_instance_methods(false).sort,
    "private" => c.private_instance_methods(false).sort,
    "singleton" => c.singleton_methods(false).sort,
    "active_record" => c < ActiveRecord::Base ? true : false,
    "active_job" => c < ActiveJob::Base ? true : false
  }]
end
File.write(ARGV.fetch(1), JSON.pretty_generate("autoload" => autoload, "surface" => surface))
puts "R7D BOOT RUNNER OK #{names.size} constants"
