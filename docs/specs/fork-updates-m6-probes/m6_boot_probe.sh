#!/usr/bin/env bash
# Probe for fork-updates-m6 (Rails 8.1 upgrade): every environment boots on Rails 8.1 with
# the old framework defaults and without deprecation warnings.
#   production, staging  - offline, eager_load (all app code incl. plugins);
#   development, test    - from a throwaway copy of the tracked tree (i18n-js writes into it).
# For each boot the probe prints one line and checks it:
#   RAILS=<Rails.version> LD=<config.loaded_config_version> EL=<eager_load> VIPS=<available>/<guarded>
#   - RAILS is 8.1.x (>= 8.1.4.1), LD stays 7.0 (load_defaults is the next milestone);
#   - VIPS: ruby-vips loads and libvips can block untrusted loaders (Active Storage 8.1 refuses
#     to boot otherwise), i.e. "true/true" in the test image that ships libvips 8.14;
#   - no deprecation warning at all: ActiveSupport::Deprecation#warn is wrapped before the app
#     loads, so silenced deprecators (production report_deprecations = false) are caught too,
#     and no "DEPRECATION WARNING" text appears in the output (Dotenv::Railtie and friends).
# Usage (from the repo root): bash docs/specs/fork-updates-m6-probes/m6_boot_probe.sh
set -euo pipefail
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
BUNDLE_DIR=${CHASKIQ_M6_BUNDLE:-$HOME/.cache/chaskiq-m6/bundle}
KEY=$(printf 'a%.0s' $(seq 64))
COPY=""
cleanup() { if [ -n "$COPY" ] && [ -d "$COPY" ]; then rm -rf -- "$COPY"; fi; }
trap cleanup EXIT

RUBY='require "active_support"
require "active_support/deprecation"
ActiveSupport::Deprecation.prepend(Module.new do
  def warn(message = nil, callstack = nil)
    $stdout.puts "PROBE-DEPRECATION: #{message.to_s.lines.first.to_s.strip}"
    super
  end
end)
require "./config/application"
Rails.application.initialize!
vips = begin
  require "active_storage/vips" unless defined?(ActiveStorage::VIPS_AVAILABLE)
  ActiveStorage::VIPS_AVAILABLE
rescue LoadError
  "n/a"
end
guard = defined?(Vips) && Vips.respond_to?(:block_untrusted)
puts "RAILS=#{Rails.version} LD=#{Rails.application.config.loaded_config_version} EL=#{Rails.application.config.eager_load} VIPS=#{vips}/#{guard}"'

run() {
  local env=$1 mount=$2; shift 2
  docker run --rm --network none --user "$(id -u):$(id -g)" \
    -e HOME=/tmp -e BUNDLE_PATH=/bundle -e RAILS_ENV="$env" -e RAILS_LOG_TO_STDOUT=1 \
    -e SECRET_KEY_BASE="$KEY" -e AWS_ACCESS_KEY_ID=probekey -e AWS_SECRET_ACCESS_KEY=probesecret \
    -e AWS_S3_REGION=eu-west-3 -e AWS_S3_BUCKET=probe -e HOST=http://localhost:3000 \
    -e DATABASE_URL=postgres://u:p@127.0.0.1:1/x -e REDIS_URL=redis://127.0.0.1:1/0 \
    -e DISABLE_AUTOLOAD_APPSTORE=true -e PROBE_RUBY="$RUBY" "$@" \
    -v "$BUNDLE_DIR:/bundle" -v "$mount" -w /app chaskiq-test:m1 \
    bash -c 'bundle exec ruby -e "$PROBE_RUBY"'
}
fail() { printf '%s\n' "$2" | tail -25; echo "FAIL: $1"; exit 1; }
check() {
  local env=$1 el=$2 out=$3
  printf '%s\n' "$out" | grep -Eq "^RAILS=8\.1\.([4-9]|[1-9][0-9])(\.[0-9]+)* LD=7\.0 EL=$el VIPS=true/true$" \
    || fail "$env: expected RAILS=8.1.x (>= 8.1.4.1) LD=7.0 EL=$el VIPS=true/true" "$out"
  local v
  v=$(printf '%s\n' "$out" | sed -n 's/^RAILS=\([0-9.]*\) .*/\1/p')
  ruby_ge=$(printf '%s\n' "$v" "8.1.4.1" | sort -V | head -1)
  [ "$ruby_ge" = "8.1.4.1" ] || fail "$env: Rails $v < 8.1.4.1" "$out"
  if printf '%s\n' "$out" | grep -Eq 'PROBE-DEPRECATION|DEPRECATION WARNING'; then
    fail "$env: deprecation warnings during boot" "$(printf '%s\n' "$out" | grep -E 'PROBE-DEPRECATION|DEPRECATION WARNING')"
  fi
  echo "ok $env: $(printf '%s\n' "$out" | grep '^RAILS=')"
}

out=$(run production "$ROOT:/app:ro" 2>&1) || fail "production boot crashed" "$out"
check production true "$out"
out=$(run staging "$ROOT:/app:ro" 2>&1) || fail "staging boot crashed" "$out"
check staging true "$out"
COPY=$(mktemp -d "${TMPDIR:-/tmp}/m6-bootcopy.XXXXXX")
git ls-files -z | tar --null -T - -cf - | tar -xf - -C "$COPY"
out=$(run development "$COPY:/app" 2>&1) || fail "development boot crashed" "$out"
check development false "$out"
out=$(run test "$COPY:/app" 2>&1) || fail "test boot crashed" "$out"
check test false "$out"
echo "M6 BOOT PROBE PASS"
