#!/usr/bin/env bash
# Probe for fork-updates-m12 (third-party deprecations): every environment boots on Rails 8.1
# (load_defaults 8.1) with RUBYOPT=-W:deprecated and prints no deprecation or warning line at all
# (Redis.current from nightfury, cypress_folder=, URLcrypt.key=, Ruby-level deprecations).
#   production, staging  - offline, eager_load (all app code incl. plugins);
#   development, test    - from a throwaway copy of the tracked tree (i18n-js writes into it).
# For each boot the probe prints one line and checks it:
#   RAILS=<Rails.version> LD=<loaded_config_version> EL=<eager_load> VIPS=<available>/<guarded> NF=<ns> UC=<bool>
#   - RAILS is 8.1.x (>= 8.1.4.1), LD is 8.1, VIPS is "true/true" (libvips 8.14 in the test image);
#   - NF: the Redis namespace Nightfury writes to, must be nf-<env> (key prefix of live data);
#   - UC: URLcrypt got its key at boot (ENV["urlcrypt_key"] set), must be true;
#   - no deprecation at all: ActiveSupport::Deprecation#warn is wrapped before the app loads
#     (silenced deprecators are caught too), and no output line contains "deprecat" (any case)
#     or "warning:" (any case).
# Usage (from the repo root): bash docs/specs/fork-updates-m12-probes/m12_boot_probe.sh
set -euo pipefail
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
BUNDLE_DIR=${CHASKIQ_M6_BUNDLE:-$HOME/.cache/chaskiq-m6/bundle}
IMG=chaskiq-test:m1
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
puts "RAILS=#{Rails.version} LD=#{Rails.application.config.loaded_config_version} EL=#{Rails.application.config.eager_load} VIPS=#{vips}/#{guard} NF=#{nf} UC=#{uc}"'

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
  local env=$1 el=$2 out=$3
  if printf '%s\n' "$out" | grep -Eiq 'deprecat|warning:'; then
    fail "$env: deprecation or warning lines during boot" "$(printf '%s\n' "$out" | grep -Ei 'deprecat|warning:')"
  fi
  printf '%s\n' "$out" | grep -Eq "^RAILS=8\.1\.([4-9]|[1-9][0-9])(\.[0-9]+)* LD=8\.1 EL=$el VIPS=true/true NF=nf-$env UC=true$" \
    || fail "$env: expected RAILS=8.1.x (>= 8.1.4.1) LD=8.1 EL=$el VIPS=true/true NF=nf-$env UC=true" "$out"
  local v
  v=$(printf '%s\n' "$out" | sed -n 's/^RAILS=\([0-9.]*\) .*/\1/p')
  low=$(printf '%s\n' "$v" "8.1.4.1" | sort -V | head -1)
  [ "$low" = "8.1.4.1" ] || fail "$env: Rails $v < 8.1.4.1" "$out"
  echo "ok $env: $(printf '%s\n' "$out" | grep '^RAILS=')"
}

out=$(run production "$ROOT:/app:ro" 2>&1) || fail "production boot crashed" "$out"
check production true "$out"
out=$(run staging "$ROOT:/app:ro" 2>&1) || fail "staging boot crashed" "$out"
check staging true "$out"
COPY=$(mktemp -d "${TMPDIR:-/tmp}/m12-bootcopy.XXXXXX")
git ls-files -z | tar --null -T - -cf - | tar -xf - -C "$COPY"
out=$(run development "$COPY:/app" 2>&1) || fail "development boot crashed" "$out"
check development false "$out"
out=$(run test "$COPY:/app" 2>&1) || fail "test boot crashed" "$out"
check test false "$out"
echo "M12 BOOT PROBE PASS"
