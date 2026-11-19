#!/usr/bin/env bash
# Probe for fork-updates-m4: SMTP without login and the staging Rack::Attack store.
#   1. SMTP_DELIVERY_METHOD=smtp with SMTP_USERNAME unset, for production, staging and
#      development (development from a throwaway copy of the tracked tree, i18n-js writes into
#      it): the environment boots, smtp_settings carry no authentication, and a mail delivered
#      with deliver_now reaches a real SMTP server without AUTH (mailpit) - on BASE this raises
#      "SMTP-AUTH requested but missing user name" (HTTP 500 in a request);
#   2. same three environments with SMTP_USERNAME/SMTP_PASSWORD set: authentication :login,
#      user_name and password from ENV, port and domain from SMTP_PORT/SMTP_DOMAIN;
#   3. staging with REDIS_URL (RA9, survived in m3): Rack::Attack.cache.store is its own
#      RedisCacheStore, not the Rails.cache object, and its counter key lands in that redis db.
# Usage (from the repo root): bash docs/specs/fork-updates-m4-probes/m4_boot_probe.sh [--smtp-only|--ra-only]
set -euo pipefail
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
BUNDLE_DIR=${CHASKIQ_M1_BUNDLE:-$HOME/.cache/chaskiq-m1/bundle}
KEY=$(printf 'a%.0s' $(seq 64))
ID="chqm4b-$(printf '%s' "$ROOT" | sha256sum | cut -c1-8)-$$"
MAILPIT=axllent/mailpit:v1.34.0
REDIS_IMG=redis:8.10-alpine
COPY=""
cleanup() {
  docker rm -f "$ID-mail" "$ID-redis" >/dev/null 2>&1 || :
  docker network rm "$ID" >/dev/null 2>&1 || :
  if [ -n "$COPY" ] && [ -d "$COPY" ]; then rm -rf -- "$COPY"; fi
}
trap cleanup EXIT
fail() { printf '%s\n' "$2" | tail -25; echo "FAIL: $1"; exit 1; }
want() { printf '%s\n' "$3" | grep -Eq "$2" || fail "$1" "$3"; }

SMTP_RUBY='require "./config/application"
Rails.application.initialize!
s = ActionMailer::Base.smtp_settings
out = "DM=#{ActionMailer::Base.delivery_method} AUTH=#{s[:authentication].inspect} USER=#{s[:user_name].inspect} PASS=#{s[:password].inspect} PORT=#{s[:port].inspect} DOMAIN=#{s[:domain].inspect}"
if ENV["PROBE_DELIVER"] == "1"
  begin
    ActionMailer::Base.perform_deliveries = true # development ships with deliveries off
    ActionMailer::Base.mail(from: "probe@example.com", to: "to@example.com", subject: ENV["PROBE_SUBJECT"], body: "b").deliver_now
    out += " DELIVERED=1"
  rescue StandardError => e
    out += " DELIVER_ERROR=#{e.class}: #{e.message}"
  end
end
puts out'

STORE_RUBY='require "./config/application"
Rails.application.initialize!
st = Rack::Attack.cache.store
inner = st.respond_to?(:__getobj__) ? st.__getobj__ : st
a = Rack::Attack.cache.count("m4probe-staging", 3600)
puts "RA_INNER=#{inner.class} RAILS_CACHE=#{Rails.cache.class} SAME_AS_RAILS_CACHE=#{inner.equal?(Rails.cache)} COUNT=#{a}"'

run() {
  local env=$1 mount=$2 ruby=$3; shift 3
  docker run --rm --network "$ID" --user "$(id -u):$(id -g)" \
    -e HOME=/tmp -e BUNDLE_PATH=/bundle -e RAILS_ENV="$env" -e RAILS_LOG_TO_STDOUT=1 \
    -e SECRET_KEY_BASE="$KEY" -e AWS_ACCESS_KEY_ID=probekey -e AWS_SECRET_ACCESS_KEY=probesecret \
    -e AWS_S3_REGION=eu-west-3 -e AWS_S3_BUCKET=probe -e HOST=http://localhost:3000 \
    -e DATABASE_URL=postgres://u:p@127.0.0.1:1/x \
    -e DISABLE_AUTOLOAD_APPSTORE=true -e PROBE_RUBY="$ruby" "$@" \
    -v "$BUNDLE_DIR:/bundle" -v "$mount" -w /app chaskiq-test:m1 \
    bash -c 'bundle exec ruby -e "$PROBE_RUBY"'
}
mail_count() {
  docker run --rm --network "$ID" --user "$(id -u):$(id -g)" chaskiq-test:m1 \
    curl -fsS "http://smtp:8025/api/v1/search?query=subject:$1" | jq -r '.messages_count'
}

MODE=${1:-}
docker network create "$ID" >/dev/null
COPY=$(mktemp -d "${TMPDIR:-/tmp}/m4-devcopy.XXXXXX")
git ls-files -z | tar --null -T - -cf - | tar -xf - -C "$COPY"

if [ "$MODE" != "--ra-only" ]; then
  docker run -d --name "$ID-mail" --network "$ID" --network-alias smtp "$MAILPIT" >/dev/null
  for _ in $(seq 1 30); do
    docker run --rm --network "$ID" --user "$(id -u):$(id -g)" chaskiq-test:m1 curl -fsS http://smtp:8025/livez >/dev/null 2>&1 && break
    sleep 1
  done
  for env in production staging development; do
    if [ "$env" = development ]; then mount="$COPY:/app"; else mount="$ROOT:/app:ro"; fi
    subj="m4noauth$env"
    out=$(run "$env" "$mount" "$SMTP_RUBY" -e REDIS_URL=redis://127.0.0.1:1/0 -e SMTP_DELIVERY_METHOD=smtp \
      -e SMTP_ADDRESS=smtp -e SMTP_PORT=1025 -e PROBE_DELIVER=1 -e PROBE_SUBJECT="$subj" 2>&1) \
      || fail "$env boot (SMTP without login) crashed" "$out"
    want "$env SMTP without SMTP_USERNAME: no authentication, mail delivered" \
      '^DM=smtp AUTH=nil .*PORT=1025 .*DELIVERED=1$' "$out"
    n=$(mail_count "$subj")
    [ "$n" = 1 ] || fail "$env: mailpit holds $n messages with subject $subj, expected 1" "$out"
    out=$(run "$env" "$mount" "$SMTP_RUBY" -e REDIS_URL=redis://127.0.0.1:1/0 -e SMTP_DELIVERY_METHOD=smtp \
      -e SMTP_ADDRESS=smtp -e SMTP_PORT=2525 -e SMTP_DOMAIN=mail.example.org \
      -e SMTP_USERNAME=probeuser -e SMTP_PASSWORD=probepass 2>&1) \
      || fail "$env boot (SMTP with login) crashed" "$out"
    want "$env SMTP with SMTP_USERNAME: login auth from ENV" \
      '^DM=smtp AUTH=:login USER="probeuser" PASS="probepass" PORT=2525 DOMAIN="mail.example.org"$' "$out"
  done
  [ "$MODE" = "--smtp-only" ] && { echo "M4 SMTP PROBE PASS"; exit 0; }
fi

docker run -d --name "$ID-redis" --network "$ID" --network-alias redis "$REDIS_IMG" >/dev/null
for _ in $(seq 1 30); do
  docker exec "$ID-redis" redis-cli ping 2>/dev/null | grep -q PONG && break
  sleep 1
done
out=$(run staging "$ROOT:/app:ro" "$STORE_RUBY" -e REDIS_URL=redis://redis:6379/4 2>&1) \
  || fail "staging boot with REDIS_URL crashed" "$out"
want "staging Rack::Attack store is its own redis store (RA9)" \
  'RA_INNER=ActiveSupport::Cache::RedisCacheStore RAILS_CACHE=ActiveSupport::Cache::RedisCacheStore SAME_AS_RAILS_CACHE=false COUNT=1$' "$out"
keys=$(docker exec "$ID-redis" redis-cli -n 4 --scan --pattern '*m4probe-staging*')
test -n "$keys" || fail "no Rack::Attack counter key in redis db 4" "$(docker exec "$ID-redis" redis-cli -n 4 --scan)"
echo "M4 BOOT PROBE PASS"
