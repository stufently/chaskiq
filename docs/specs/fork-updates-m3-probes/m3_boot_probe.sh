#!/usr/bin/env bash
# Probe for fork-updates-m3: environment boots and shared Rack::Attack counters.
#   1. staging boots offline (eager_load) in the SES branch: delivery method ses or ses_v2,
#      region from AWS_S3_REGION, AWS_ACCESS_KEY_ID credentials, delivery with stubbed AWS
#      responses succeeds; with SMTP_DELIVERY_METHOD=smtp the method is smtp;
#   2. development boots (from a throwaway copy of the tracked tree, because i18n-js writes
#      into the tree) in the SES branch with the region and key from ENV;
#   3. production with REDIS_URL: Rack::Attack.cache.store is backed by that redis (counter
#      keys appear in the redis database, counts from two separate processes add up),
#      Rails.cache stays the file store and is not the Rack::Attack store;
#   4. production without REDIS_URL boots, falls back to Rails.cache (counter really grows)
#      and logs a warning that names Rack::Attack and REDIS_URL.
# Usage (from the repo root): bash docs/specs/fork-updates-m3-probes/m3_boot_probe.sh [--dev-only]
#   --dev-only runs step 2 only (used by m3_mutation_gate.py).
set -euo pipefail
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
BUNDLE_DIR=${CHASKIQ_M1_BUNDLE:-$HOME/.cache/chaskiq-m1/bundle}
KEY=$(printf 'a%.0s' $(seq 64))
ID="chqm3b-$(printf '%s' "$ROOT" | sha256sum | cut -c1-8)-$$"
COPY=""
cleanup() {
  docker rm -f "$ID-redis" >/dev/null 2>&1 || :
  docker network rm "$ID" >/dev/null 2>&1 || :
  if [ -n "$COPY" ] && [ -d "$COPY" ]; then rm -rf -- "$COPY"; fi
}
trap cleanup EXIT

MAIL_RUBY='require "./config/application"
Rails.application.initialize!
dm = ActionMailer::Base.delivery_method
out = "DM=#{dm} EL=#{Rails.application.config.eager_load}"
if %i[ses ses_v2].include?(dm)
  klass = ActionMailer::Base.delivery_methods.fetch(dm)
  settings = ActionMailer::Base.public_send("#{dm}_settings").to_h
  creds = settings[:credentials]
  key = creds.respond_to?(:access_key_id) ? creds.access_key_id : nil
  if ENV["PROBE_DELIVER"] == "1"
    adapter = klass.new(settings.merge(stub_responses: true))
    adapter.deliver!(Mail.new(from: "probe@example.com", to: "to@example.com", subject: "s", body: "b"))
    out += " REGION=#{settings[:region]} KEY=#{key} DELIVERED=1"
  else
    out += " REGION=#{settings[:region]} KEY=#{key}"
  end
end
puts out'

STORE_RUBY='require "./config/application"
Rails.application.initialize!
st = Rack::Attack.cache.store
inner = st.respond_to?(:__getobj__) ? st.__getobj__ : st
a = Rack::Attack.cache.count("m3probe-#{ENV["PROBE_TAG"]}", 3600)
b = Rack::Attack.cache.count("m3probe-#{ENV["PROBE_TAG"]}", 3600)
puts "RA_STORE=#{st.class} RA_INNER=#{inner.class} RAILS_CACHE=#{Rails.cache.class} SAME_AS_RAILS_CACHE=#{inner.equal?(Rails.cache)} COUNT=#{a},#{b}"'

run() {
  local env=$1 mount=$2 net=$3 ruby=$4; shift 4
  docker run --rm --network "$net" --user "$(id -u):$(id -g)" \
    -e HOME=/tmp -e BUNDLE_PATH=/bundle -e RAILS_ENV="$env" -e RAILS_LOG_TO_STDOUT=1 \
    -e SECRET_KEY_BASE="$KEY" -e AWS_ACCESS_KEY_ID=probekey -e AWS_SECRET_ACCESS_KEY=probesecret \
    -e AWS_S3_REGION=eu-west-3 -e AWS_S3_BUCKET=probe -e HOST=http://localhost:3000 \
    -e DATABASE_URL=postgres://u:p@127.0.0.1:1/x \
    -e DISABLE_AUTOLOAD_APPSTORE=true -e PROBE_RUBY="$ruby" "$@" \
    -v "$BUNDLE_DIR:/bundle" -v "$mount" -w /app chaskiq-test:m1 \
    bash -c 'bundle exec ruby -e "$PROBE_RUBY"'
}
fail() { printf '%s\n' "$2" | tail -25; echo "FAIL: $1"; exit 1; }
want() { printf '%s\n' "$3" | grep -Eq "$2" || fail "$1" "$3"; }

RO="$ROOT:/app:ro"
MODE=${1:-}
SES='^DM=(ses|ses_v2) EL=true REGION=eu-west-3 KEY=probekey DELIVERED=1$'

if [ "$MODE" != "--dev-only" ]; then
out=$(run staging "$RO" none "$MAIL_RUBY" -e REDIS_URL=redis://127.0.0.1:1/0 -e PROBE_DELIVER=1 2>&1) || fail "staging boot (SES branch) crashed" "$out"
want "staging SES branch" "$SES" "$out"
out=$(run staging "$RO" none "$MAIL_RUBY" -e REDIS_URL=redis://127.0.0.1:1/0 -e SMTP_DELIVERY_METHOD=smtp 2>&1) || fail "staging boot (SMTP branch) crashed" "$out"
want "staging SMTP branch" '^DM=smtp EL=true$' "$out"
fi

COPY=$(mktemp -d "${TMPDIR:-/tmp}/m3-devcopy.XXXXXX")
git ls-files -z | tar --null -T - -cf - | tar -xf - -C "$COPY"
out=$(run development "$COPY:/app" none "$MAIL_RUBY" -e REDIS_URL=redis://127.0.0.1:1/0 2>&1) || fail "development boot (SES branch) crashed" "$out"
want "development SES branch" '^DM=(ses|ses_v2) EL=false REGION=eu-west-3 KEY=probekey$' "$out"
if [ "$MODE" = "--dev-only" ]; then echo "M3 DEV BOOT PASS"; exit 0; fi

docker network create "$ID" >/dev/null
docker run -d --name "$ID-redis" --network "$ID" --network-alias redis redis:5-alpine >/dev/null
for _ in $(seq 1 30); do
  docker exec "$ID-redis" redis-cli ping 2>/dev/null | grep -q PONG && break
  sleep 1
done
REDIS="redis://redis:6379/3"
out=$(run production "$RO" "$ID" "$STORE_RUBY" -e REDIS_URL="$REDIS" -e PROBE_TAG=shared 2>&1) || fail "production boot with REDIS_URL crashed" "$out"
want "production Rack::Attack store backed by redis (first process)" 'RA_INNER=(ActiveSupport::Cache::RedisCacheStore|Redis[A-Za-z:]*) RAILS_CACHE=ActiveSupport::Cache::FileStore SAME_AS_RAILS_CACHE=false COUNT=1,2$' "$out"
out=$(run production "$RO" "$ID" "$STORE_RUBY" -e REDIS_URL="$REDIS" -e PROBE_TAG=shared 2>&1) || fail "production boot with REDIS_URL crashed (second process)" "$out"
want "production Rack::Attack counter shared between processes" 'COUNT=3,4$' "$out"
keys=$(docker exec "$ID-redis" redis-cli -n 3 --scan --pattern '*m3probe-shared*')
test -n "$keys" || fail "no Rack::Attack counter key in redis db 3" "$(docker exec "$ID-redis" redis-cli -n 3 --scan)"

out=$(run production "$COPY:/app" none "$STORE_RUBY" -e PROBE_TAG=noredis 2>&1) || fail "production boot without REDIS_URL crashed" "$out"
want "production without REDIS_URL counts via the Rails.cache fallback" 'SAME_AS_RAILS_CACHE=true COUNT=1,2$' "$out"
printf '%s\n' "$out" | grep -i 'rack::attack' | grep -q 'REDIS_URL' || fail "no warning naming Rack::Attack and REDIS_URL without REDIS_URL" "$out"

echo "M3 BOOT PROBE PASS"
