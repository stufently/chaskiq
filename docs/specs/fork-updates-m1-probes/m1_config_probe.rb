# frozen_string_literal: true

# Probe for fork-updates-m1, package B and the dev-environment items
# (SMTP from ENV, WS typo, App.tsx null-safe metas, docker-compose, .gitattributes).
# Run from the repository root with plain ruby (no bundle needed).
require "yaml"

fails = []

# --- SMTP settings in production (antonburesh 8ac45dd0f3, neutral defaults) ---
prod = File.read("config/environments/production.rb")
fails << "production.rb must not mention wowvendor" if prod.downcase.include?("wowvendor")
block = prod[/config\.action_mailer\.smtp_settings\s*=\s*(\{.*?^\s*\})/m, 1]
if block.nil?
  fails << "smtp_settings hash literal not found in production.rb"
else
  smtp = lambda do |env|
    saved = ENV.to_h
    %w[SMTP_PORT SMTP_DOMAIN SMTP_ADDRESS SMTP_USERNAME SMTP_PASSWORD].each { |k| ENV.delete(k) }
    env.each { |k, v| ENV[k] = v }
    eval(block) # rubocop:disable Security/Eval -- probe evaluates the literal from the repo file
  ensure
    ENV.replace(saved)
  end
  unset = smtp.call({})
  fails << "SMTP_PORT unset: port must stay the current effective default 25 (or be absent), got #{unset[:port].inspect}" unless [nil, 25].include?(unset[:port])
  fails << "SMTP_DOMAIN unset: domain must be absent or localhost.localdomain, got #{unset[:domain].inspect}" unless [nil, "localhost.localdomain"].include?(unset[:domain])
  set = smtp.call("SMTP_PORT" => "2525", "SMTP_DOMAIN" => "mail.example.org", "SMTP_ADDRESS" => "smtp.example.org",
                  "SMTP_USERNAME" => "u", "SMTP_PASSWORD" => "p")
  fails << "SMTP_PORT=2525 must give Integer 2525, got #{set[:port].inspect}" unless set[:port] == 2525
  fails << "SMTP_DOMAIN must be used, got #{set[:domain].inspect}" unless set[:domain] == "mail.example.org"
  fails << "address/user_name/password must still come from ENV" unless set.values_at(:address, :user_name, :password) == %w[smtp.example.org u p]
  fails << "authentication :login and enable_starttls_auto true must be kept" unless set[:authentication] == :login && set[:enable_starttls_auto] == true
end

# --- development.rb: WS typo fixed, asset_host untouched ---
dev = File.read("config/environments/development.rb")
fails << "development.rb still has the locahost typo" if dev.include?("locahost")
fails << "development.rb must default WS to ws://localhost:3000/cable" unless dev.include?("ws://localhost:3000/cable")
fails << "development.rb: config.action_controller.asset_host = host must stay active (not in scope)" unless dev.match?(/^\s*config\.action_controller\.asset_host = host\s*$/)

# --- App.tsx null-safe meta reads (PriDebnath c236c1ff18) ---
app = File.read("app/javascript/src/App.tsx")
fails << "App.tsx: chaskiq-host meta must be read null-safely (no .querySelector(...).getAttribute chain)" if app.match?(/querySelector\(\s*"meta\[name='chaskiq-host'\]"\s*\)\s*\.getAttribute/)
fails << "App.tsx: must fall back to window.location.origin when chaskiq-host meta is missing" unless app.include?("window.location.origin")
fails << "App.tsx: auth0 metas must be typed, not @ts-ignore'd" if app.match?(/@ts-ignore\s*\n\s*const auth0/)

# --- docker-compose.yml (Haris 7cef190ede + compose part of f877c09b8c) ---
# Named volume by default; POSTGRES_DATA=~/apps/postgres keeps an existing bind-mounted database reachable.
compose = YAML.load_file("docker-compose.yml", aliases: true)
xapp = compose["x-app"] || {}
fails << "docker-compose: x-app must not mount tmpfs /tmp" if xapp.key?("tmpfs")
pg_vols = Array(compose.dig("services", "postgres", "volumes"))
fails << "docker-compose: postgres data must be ${POSTGRES_DATA:-postgres}:/var/lib/postgresql/data, got #{pg_vols.inspect}" unless pg_vols.include?("${POSTGRES_DATA:-postgres}:/var/lib/postgresql/data") && pg_vols.none? { |v| v.to_s.start_with?("~") }
env = compose.dig("services", "rails", "environment") || {}
fails << "docker-compose: backend WEB_CONCURRENCY must be 0, got #{env['WEB_CONCURRENCY'].inspect}" unless env["WEB_CONCURRENCY"].to_s == "0"
fails << "docker-compose: backend HOST must be http://localhost:3000" unless env["HOST"] == "http://localhost:3000"
fails << "docker-compose: backend WS must be ws://localhost:3000/cable" unless env["WS"] == "ws://localhost:3000/cable"
fails << "docker-compose: image name must stay chaskiq/chaskiq:1.1.0" unless xapp["image"] == "chaskiq/chaskiq:1.1.0"

# --- .gitattributes (PriDebnath) ---
if File.exist?(".gitattributes")
  ga = File.read(".gitattributes").lines.map(&:strip)
  ["* text=auto eol=lf", "*.sh text eol=lf", "bin/* text eol=lf"].each do |rule|
    fails << ".gitattributes must contain the rule: #{rule}" unless ga.include?(rule)
  end
else
  fails << ".gitattributes missing"
end

if fails.empty?
  puts "CONFIG PROBE PASS"
else
  puts fails
  exit 1
end
