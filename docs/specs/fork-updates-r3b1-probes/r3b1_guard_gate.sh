#!/usr/bin/env bash
# Runs r3b1_presence_guard.rb in the booted app (test env), in the bin/ci-local image with postgres
# and redis as in `bin/ci-local --only rspec`, against the working tree.
#
#   CHASKIQ_R3B1_CACHE=~/.cache/chaskiq-r3b1-ci bash r3b1_guard_gate.sh
#
# Pass = "R3B1 EAGER LOAD OK" and "R3B1 GUARD PASS <n> classes" (n > 0), exit 0.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
CACHE=${CHASKIQ_R3B1_CACHE:-$HOME/.cache/chaskiq-r3b1-ci}
IMG="chaskiq-ci-local:ruby-$(tr -d '[:space:]' < .ruby-version)-ubuntu-26.04"
docker image inspect "$IMG" >/dev/null 2>&1 || { echo "FAIL: image $IMG missing (built by bin/ci-local)"; exit 1; }
test -d "$CACHE/bundle-ubuntu-26.04" || { echo "FAIL: gem cache $CACHE/bundle-ubuntu-26.04 missing"; exit 1; }
W=tmp/r3b1-guard
rm -rf "$W"
mkdir -p "$W"
P=${HERE#"$ROOT"/}
ID="r3b1guard-$$-$(date +%s)"
cleanup() { docker rm -f "$ID-pg" "$ID-redis" >/dev/null 2>&1 || :; docker network rm "$ID" >/dev/null 2>&1 || :; }
trap cleanup EXIT INT TERM
docker network create "$ID" >/dev/null
docker run -d --name "$ID-pg" --network "$ID" --network-alias pg -e POSTGRES_PASSWORD=postgres \
  --tmpfs /var/lib/postgresql/data postgres:14-alpine >/dev/null
docker run -d --name "$ID-redis" --network "$ID" --network-alias redis redis:8.10-alpine >/dev/null
ready=""
for _ in $(seq 1 60); do
  if docker exec "$ID-pg" pg_isready -U postgres -h 127.0.0.1 >/dev/null 2>&1; then ready=1; break; fi
  sleep 1
done
[ -n "$ready" ] || { echo "FAIL: postgres did not become ready"; exit 1; }
# Create the bind-mount target as our user: if Docker creates it, it is root-owned in the clone.
mkdir -p "$ROOT/vendor/bundle"
rc=0
docker run --rm --init --user "$(id -u):$(id -g)" --network "$ID" \
  -e HOME=/tmp -e BUNDLE_PATH=/app/vendor/bundle -e BUNDLE_FROZEN=true \
  -e BUNDLE_BUILD__SCOUT_APM="--with-cflags=-std=gnu17" -e RAILS_ENV=test \
  -e DATABASE_URL=postgres://postgres:postgres@pg:5432/test -e REDIS_URL=redis://redis:6379/0 -e P="$P" \
  -v "$ROOT:/app" -v "$CACHE/bundle-ubuntu-26.04:/app/vendor/bundle" -w /app "$IMG" bash -c '
    set -e
    bundle install --quiet
    bin/rails db:prepare >/dev/null
    bin/rails runner "$P/r3b1_presence_guard.rb" "$P/r3b1_config.json"' > "$W/out.txt" 2>&1 || rc=$?
grep -E 'R3B1 |FAIL' "$W/out.txt" | head -40 || :
[ "$rc" = 0 ] || { echo "FAIL: run exited $rc"; tail -20 "$W/out.txt"; exit 1; }
grep -qx 'R3B1 EAGER LOAD OK' "$W/out.txt" || { echo "FAIL: eager load did not finish"; exit 1; }
grep -qE '^R3B1 GUARD PASS [1-9][0-9]* classes$' "$W/out.txt" || { echo "FAIL: no guard verdict"; exit 1; }
echo "R3B1 GUARD GATE PASS"
