#!/usr/bin/env bash
# Kill gate for mut-m9-m14b: every mutant of kill_table.json, re-applied here from the patches of this
# directory (never from the executor's files), must be killed by an assertion in the specs the
# executor recorded for it (tmp/mutants-b/manifest.json; killed_new - in its test_added).
#
#   CHASKIQ_MUTB_CACHE=~/.cache/chaskiq-mutb-ci bash mutb_kill_gate.sh [--only M024,M028] [--jobs FILE]
#
# Jobs come from `mutb_probe.py jobs` (or --jobs FILE for the author's pre-check); --only keeps the
# listed ids (a quick check while writing tests - the criterion runs without it). Works on a copy
# (git archive HEAD -> tmp/mutb-kill/tree); runs in the bin/ci-local image with postgres/redis.
# Pass = "MUTB KILL PASS k/k killed" with k = jobs, exit 0.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
CACHE=${CHASKIQ_MUTB_CACHE:-$HOME/.cache/chaskiq-mutb-ci}
IMG="chaskiq-ci-local:ruby-$(tr -d '[:space:]' < .ruby-version)-ubuntu-26.04"
docker image inspect "$IMG" >/dev/null 2>&1 || { echo "FAIL: image $IMG missing (built by bin/ci-local)"; exit 1; }
test -d "$CACHE/bundle-ubuntu-26.04" || { echo "FAIL: gem cache $CACHE/bundle-ubuntu-26.04 missing"; exit 1; }
W=tmp/mutb-kill
rm -rf "$W"
mkdir -p "$W/tree" "$W/out" vendor/bundle
ONLY="" JOBS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --only) ONLY=${2:?--only IDS}; shift 2 ;;
    --jobs) JOBS=${2:?--jobs FILE}; shift 2 ;;
    *) echo "FAIL: unknown argument $1"; exit 1 ;;
  esac
done
if [ -n "$JOBS" ]; then
  cp "$JOBS" "$W/jobs-all.json"
else
  python3 -I "$HERE/mutb_probe.py" jobs > "$W/jobs-all.json" || { cat "$W/jobs-all.json"; exit 1; }
fi
if [ -n "$ONLY" ]; then
  jq --arg ids "$ONLY" '($ids | split(",")) as $k | map(select(.id as $i | $k | index($i)))' "$W/jobs-all.json" > "$W/jobs.json"
  [ "$(jq 'length' "$W/jobs.json")" -gt 0 ] || { echo "FAIL: --only $ONLY matches no job"; exit 1; }
else
  cp "$W/jobs-all.json" "$W/jobs.json"
fi
git archive HEAD | tar -x -C "$W/tree"
cp -r "$HERE/patches" "$W/patches"
cp "$HERE/mutb_kill.rb" "$W/"
N=$(jq 'length' "$W/jobs.json")
K=$(jq 'length' "$HERE/kill_table.json")
if [ -z "$ONLY" ] && [ -z "$JOBS" ] && [ "$N" != "$K" ]; then
  echo "FAIL: the executor manifest gives $N of the $K kill-table mutants (tmp/mutants-b/manifest.json)"; exit 1
fi
ID="mutbkill-$$-$(date +%s)"
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
rc=0
docker run --rm --init --user "$(id -u):$(id -g)" --network "$ID" \
  -e HOME=/tmp -e BUNDLE_PATH=/bundle -e BUNDLE_FROZEN=true -e BUNDLE_GEMFILE=/app/$W/tree/Gemfile \
  -e BUNDLE_BUILD__SCOUT_APM="--with-cflags=-std=gnu17" -e RAILS_ENV=test \
  -e DATABASE_URL=postgres://postgres:postgres@pg:5432/test -e REDIS_URL=redis://redis:6379/0 \
  -v "$ROOT:/app" -v "$CACHE/bundle-ubuntu-26.04:/bundle" -w "/app/$W/tree" "$IMG" bash -c '
    set -e
    bundle install --quiet
    bin/rails db:prepare >/dev/null
    ruby ../mutb_kill.rb ../jobs.json ../patches ../out' > "$W/out.txt" 2>&1 || rc=$?
grep -E '^(MUTB |SURVIVED|FAIL)' "$W/out.txt" | head -120 || :
[ "$rc" = 0 ] || { echo "FAIL: run exited $rc"; tail -5 "$W/out.txt"; exit 1; }
grep -qx "MUTB KILL PASS $N/$N killed" "$W/out.txt" || { echo "FAIL: not all $N mutants killed"; exit 1; }
echo "MUTB KILL GATE PASS"
