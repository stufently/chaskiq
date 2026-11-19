# frozen_string_literal: true

source "https://rubygems.org"
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby "3.3.5"

# gem 'google-protobuf', git: 'https://github.com/google/protobuf'

# gem "grpc", force_ruby_platform: true
# Bundle edge Rails instead: gem 'rails', github: 'rails/rails'
gem "anycable-rails", ">= 1.5.5"

gem "pg"
gem "json", "< 3"
gem "rails", "~> 8.1.4", ">= 8.1.4.1"
gem "uri", "~> 1.1"

# Use sqlite3 as the database for Active Record
# gem "sqlite3", group: "test"
# gem "sqlite3", "~> 1.3.6"
# Use Puma as the app server
gem "haml"
gem "jsbundling-rails", ">= 1.2.2"
gem "kredis", "~> 1.3"
gem "propshaft", ">= 0.8.0"
gem "puma", "~> 6.0"
# gem "falcon"
gem "sassc"
gem "tailwindcss-rails"

gem "devise", ">= 4.9.4" # , "4.7.1" # github: "plataformatec/devise"
# Use CoffeeScript for .coffee assets and views
# gem 'coffee-rails', '~> 4.2'
# Turbolinks makes navigating your web application faster. Read more: https://github.com/turbolinks/turbolinks
# gem "turbolinks", "~> 5"
# Build JSON APIs with ease. Read more: https://github.com/rails/jbuilder
gem "jbuilder"
# gem 'haml'
# Use Redis adapter to run Action Cable in production
gem "redis", "~> 4.0"
gem "redis-namespace", "~> 1.8"
gem "redis-objects", "~> 1.5"
# Use ActiveModel has_secure_password
# gem 'bcrypt', '~> 3.1.7'
gem "nightfury", github: "michelson/nightfury" # "~> 1.0"

# gem 'tabs', github: 'michelson/tabs', branch: "upgrade"

gem "action_policy-graphql", "~> 0.4"
gem "goldiloader"
gem "graphiql-rails", ">= 1.10.0", group: :development
gem "graphql", "~> 2.1"

gem "nokogiri", force_ruby_platform: true

# Use Capistrano for deployment
# gem 'capistrano-rails', group: :development
# gem 'tunable'
gem "aasm"
gem "acts_as_list", "~> 0.9.19"
gem "acts-as-taggable-on", "~> 13.0"
# github: "mbleigh/acts-as-taggable-on", branch: "support_rails_7-1"
gem "deep_cloneable"
gem "friendly_id", "~> 5.2"
gem "groupdate"
gem "pg_search"
gem "phonelib"
gem "ransack"

gem "searchkick"

# gem "elasticsearch", "7.12" # select one
gem "opensearch-ruby", ">= 3.1.0" # select one

gem "browser", "~> 2.5"
gem "geocoder", "~> 1.6"
gem "geoip"
gem "truemail"

gem "google-cloud-dialogflow", ">= 1.7.0"
gem "twilio-ruby", "~> 5.67.0"

gem "jwe"
gem "jwt"

# AUTH
# gem 'devise-jwt', '~> 0.5.9'
gem "devise_invitable", "~> 2.0", ">= 2.0.9"
gem "doorkeeper", "~> 5.6.0"
gem "oauth", "~> 0.5.5"
gem "omniauth-oauth2", ">= 1.9.0"

gem "image_processing", "~> 1.12"
gem "sidekiq", ">= 7.2.0" # , "~> 6.5"
# gem "sidekiq-cron"

gem "emoji_data", github: "chaskiq/emoji_data.rb"
gem "roadie"
gem "roadie-rails", "~> 3.4"
gem "urlcrypt"

gem "aws-sdk-rails", ">= 3.9.1"
gem "aws-actionmailer-ses", "~> 1.2"
gem "aws-sdk-s3", "~> 1.208", ">= 1.208.0"

gem "mini_magick", "~> 5.1"

gem "active_importer"
gem "faraday", ">= 2.14.1"
gem "http"
gem "net-http", ">= 0.4.0"
gem "roo", "~> 2.8", ">= 2.8.3", git: "https://github.com/roo-rb/roo.git"
gem "ruby-oembed"

gem "mustache"

gem "chronic", "~> 0.10.2"
gem "fast_page", "~> 0.1.5"
gem "kaminari", "~> 1.2"

gem "timezone", "~> 1.2"

gem "bugsnag" # , '~> 6.11'
# gem "email_reply_parser", "~> 0.5.9"
gem "email_reply_trimmer"
gem "rack", "~> 2.2", ">= 2.2.25"
gem "rack-attack", "~> 6.8"
gem "rack-cors", "~> 2.0", ">= 2.0.0"

gem "biz", "~> 1.8"
# gem "i18n-js"
gem "i18n-js", "~> 4.0.0.alpha1"

gem "globalize", "~> 7.1"

# To use Stripe, also include:
gem "stripe", "~> 6.0"
# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", ">= 1.1.0", require: false

gem "dotenv-rails", ">= 3.0.0", groups: %i[development test]

group :development, :test do
  # Call 'byebug' anywhere in the code to stop execution and get a debugger console
  # gem 'byebug', platforms: [:mri, :mingw, :x64_mingw]
  gem "cypress-on-rails", "~> 1.17", ">= 1.17.0"
  gem "execjs"
  gem "pry"
  # gem "debug", platforms: %i[mri mingw x64_mingw]
end

group :development do
  # gem "rack-mini-profiler", "~> 2.0"
  # Access an interactive console on exception pages or by calling 'console' anywhere in the code.
  gem "listen" # , ">= 3.0.5", "< 3.2"
  gem "web-console", ">= 3.3.0"
  # Spring speeds up development by keeping your application running in the background. Read more: https://github.com/rails/spring
  gem "spring"
end

group :test do
  gem "faker", github: "stympy/faker", group: %i[development test]
  gem "rspec-rails", ">= 6.0.4" # , git: 'https://github.com/rspec/rspec-rails', branch: '4-0-dev'
  %w[rspec-core rspec-expectations rspec-mocks rspec-support].each do |lib|
    gem lib # , :git => "https://github.com/rspec/#{lib}.git", :branch => 'master'
  end
  gem "brakeman"
  gem "code-scanning-rubocop", require: false
  gem "database_cleaner-active_record"
  gem "database_cleaner-redis"
  gem "factory_bot_rails", ">= 6.4.4"
  gem "rubocop", ">= 1.66.0", require: false
  gem "rubocop-performance", ">= 1.20.0", require: false
  gem "rubocop-rails", ">= 2.22.0", require: false
  gem "rubocop-rspec", ">= 2.25.0", require: false
  gem "shoulda"
  gem "shoulda-matchers"
  gem "webmock"
end

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "php_serialize", "~> 1.2"
gem "scout_apm"
gem "tzinfo-data", platforms: %i[mingw mswin x64_mingw jruby]
