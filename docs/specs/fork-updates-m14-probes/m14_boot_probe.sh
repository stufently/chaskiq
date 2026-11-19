#!/usr/bin/env bash
# Probe for fork-updates-m14 (Ruby 4.0): every environment boots on Ruby 4.0.x (>= 4.0.10) with
# Rails 8.1 (load_defaults 8.1), rack 3.2, YJIT on in production/staging (Rails 8.1 default),
# RUBYOPT=-W:deprecated, and prints no deprecation or warning line at all (bundler, bundled gems,
# chilled strings).
#   production, staging  - offline, eager_load (all app code incl. plugins);
#   development, test    - from a throwaway copy of the tracked tree (i18n-js writes into it).
# For each boot the probe prints one line and checks it:
#   RAILS=<Rails.version> LD=<loaded_config_version> EL=<eager_load> VIPS=<available>/<guarded> NF=<ns> UC=<bool> RACK=<release> RUBY=<RUBY_VERSION> YJIT=<enabled>
#   - RAILS is 8.1.x (>= 8.1.4.1), LD is 8.1, VIPS is "true/true" (libvips 8.14 in the test image);
#   - NF: the Redis namespace Nightfury writes to, must be nf-<env> (key prefix of live data);
#   - UC: URLcrypt got its key at boot (ENV["urlcrypt_key"] set), must be true;
#   - RACK is 3.2.x >= 3.2.8; RUBY is 4.0.x >= 4.0.10; YJIT true in production/staging, false otherwise;
#   - no deprecation at all: ActiveSupport::Deprecation#warn is wrapped before the app loads
#     (silenced deprecators are caught too), and no output line contains "deprecat" (any case)
#     or "warning:" (any case).
# Usage (from the repo root): bash docs/specs/fork-updates-m14-probes/m14_boot_probe.sh
set -euo pipefail
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
BUNDLE_DIR=${CHASKIQ_M14_BUNDLE:-$HOME/.cache/chaskiq-m14/bundle}
IMG=${CHASKIQ_TEST_IMAGE:-chaskiq-test:m1}
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
nf = begin
  Nightfury.redis.namespace
rescue StandardError => e
  "error:#{e.class}"
end
uc = !ENV["urlcrypt_key"].to_s.empty?
spec = ->(g) { Gem.loaded_specs[g]&.version.to_s }
puts "RAILS=#{Rails.version} LD=#{Rails.application.config.loaded_config_version} EL=#{Rails.application.config.eager_load} VIPS=#{vips}/#{guard} NF=#{nf} UC=#{uc} RACK=#{Rack.release} RUBY=#{RUBY_VERSION} YJIT=#{defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled? ? true : false}"'

run() {
  local env=$1 mount=$2; shift 2
  docker run --rm --network none --user "$(id -u):$(id -g)" \
    -e HOME=/tmp -e BUNDLE_PATH=/bundle -e RAILS_ENV="$env" -e RAILS_LOG_TO_STDOUT=1 \
    -e SECRET_KEY_BASE="$KEY" -e AWS_ACCESS_KEY_ID=probekey -e AWS_SECRET_ACCESS_KEY=probesecret \
    -e AWS_S3_REGION=eu-west-3 -e AWS_S3_BUCKET=probe -e HOST=http://localhost:3000 \
    -e DATABASE_URL=postgres://u:p@127.0.0.1:1/x -e REDIS_URL=redis://127.0.0.1:1/0 \
    -e DISABLE_AUTOLOAD_APPSTORE=true -e RUBYOPT=-W:deprecated -e PROBE_RUBY="$RUBY" "$@" \
    -v "$BUNDLE_DIR:/bundle" -v "$mount" -w /app "$IMG" \
    bash -c 'bundle exec ruby -e "$PROBE_RUBY"'
}
fail() { printf '%s\n' "$2" | tail -25; echo "FAIL: $1"; exit 1; }
check() {
  local env=$1 el=$2 out=$3 yjit=false
  case $env in production|staging) yjit=true ;; esac
  if printf '%s\n' "$out" | grep -Eiq 'deprecat|warning:'; then
    fail "$env: deprecation or warning lines during boot" "$(printf '%s\n' "$out" | grep -Ei 'deprecat|warning:')"
  fi
  printf '%s\n' "$out" | grep -Eq "^RAILS=8\.1\.([4-9]|[1-9][0-9])(\.[0-9]+)* LD=8\.1 EL=$el VIPS=true/true NF=nf-$env UC=true RACK=3\.2\.[0-9]+ RUBY=4\.0\.[0-9]+ YJIT=$yjit$" \
    || fail "$env: expected RAILS=8.1.x (>= 8.1.4.1) LD=8.1 EL=$el VIPS=true/true NF=nf-$env UC=true RACK=3.2.x RUBY=4.0.x YJIT=$yjit" "$out"
  local v
  v=$(printf '%s\n' "$out" | sed -n 's/^RAILS=\([0-9.]*\) .*/\1/p')
  low=$(printf '%s\n' "$v" "8.1.4.1" | sort -V | head -1)
  [ "$low" = "8.1.4.1" ] || fail "$env: Rails $v < 8.1.4.1" "$out"
  r=$(printf '%s\n' "$out" | sed -n 's/^RAILS=.* RACK=\([0-9.]*\) .*/\1/p')
  low=$(printf '%s\n' "$r" "3.2.8" | sort -V | head -1)
  [ "$low" = "3.2.8" ] || fail "$env: rack $r < 3.2.8" "$out"
  r=$(printf '%s\n' "$out" | sed -n 's/^RAILS=.* RUBY=\([0-9.]*\) .*/\1/p')
  low=$(printf '%s\n' "$r" "4.0.10" | sort -V | head -1)
  [ "$low" = "4.0.10" ] || fail "$env: Ruby $r < 4.0.10" "$out"
  echo "ok $env: $(printf '%s\n' "$out" | grep '^RAILS=')"
}

out=$(run production "$ROOT:/app:ro" 2>&1) || fail "production boot crashed" "$out"
check production true "$out"
out=$(run staging "$ROOT:/app:ro" 2>&1) || fail "staging boot crashed" "$out"
check staging true "$out"
COPY=$(mktemp -d "${TMPDIR:-/tmp}/m14-bootcopy.XXXXXX")
git ls-files -z | tar --null -T - -cf - | tar -xf - -C "$COPY"
out=$(run development "$COPY:/app" 2>&1) || fail "development boot crashed" "$out"
check development false "$out"
out=$(run test "$COPY:/app" 2>&1) || fail "test boot crashed" "$out"
check test false "$out"
echo "M14 BOOT PROBE PASS"
