#!/usr/bin/env bash
# Test gate for fork-updates-r5: characterization specs green on BASE and the tree, fix specs red on
# BASE and green on the tree, every mutant of r5_config.json killed (r5_tests.rb).
#
#   CHASKIQ_R5_CACHE=~/.cache/chaskiq-r5-ci bash r5_tests_gate.sh <BASE_SHA>
#
# Works on a copy: HEAD via git archive to tmp/r5-tests/tree, BASE versions of the app files to
# tmp/r5-tests/base; runs in the bin/ci-local image with postgres/redis as in `bin/ci-local --only
# rspec`. Pass = "R5 TREE PASS", "R5 BASE PASS", "R5 MUTANTS PASS k/k killed" with k = mutants in
# r5_config.json, exit 0.
set -euo pipefail
BASE=${1:?usage: r5_tests_gate.sh <BASE_SHA>}
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
CACHE=${CHASKIQ_R5_CACHE:-$HOME/.cache/chaskiq-r5-ci}
IMG="chaskiq-ci-local:ruby-$(tr -d '[:space:]' < .ruby-version)-ubuntu-26.04"
docker image inspect "$IMG" >/dev/null 2>&1 || { echo "FAIL: image $IMG missing (built by bin/ci-local)"; exit 1; }
test -d "$CACHE/bundle-ubuntu-26.04" || { echo "FAIL: gem cache $CACHE/bundle-ubuntu-26.04 missing"; exit 1; }
W=tmp/r5-tests
rm -rf "$W"
mkdir -p "$W/tree" "$W/base" "$W/out" vendor/bundle
git archive HEAD | tar -x -C "$W/tree"
jq -r '.app_files[]' "$HERE/r5_config.json" > "$W/app_files"
while IFS= read -r f; do
  mkdir -p "$W/base/$(dirname "$f")"
  git show "$BASE:$f" > "$W/base/$f"
done < "$W/app_files"
cp "$HERE/r5_config.json" "$HERE/r5_tests.rb" "$W/"
MUTS=$(jq '.mutants | length' "$HERE/r5_config.json")
ID="r5tests-$$-$(date +%s)"
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
    ruby ../r5_tests.rb ../r5_config.json ../base ../out' > "$W/out.txt" 2>&1 || rc=$?
grep -E '^(R5 |KILLED|FAIL)' "$W/out.txt" | head -60 || :
[ "$rc" = 0 ] || { echo "FAIL: run exited $rc"; tail -20 "$W/out.txt"; exit 1; }
grep -qE '^R5 TREE PASS [1-9][0-9]* examples$' "$W/out.txt" || { echo "FAIL: no tree verdict"; exit 1; }
grep -qE '^R5 BASE PASS [1-9][0-9]* char / [1-9][0-9]* fix failing$' "$W/out.txt" || { echo "FAIL: no BASE verdict"; exit 1; }
grep -qx "R5 MUTANTS PASS $MUTS/$MUTS killed" "$W/out.txt" || { echo "FAIL: not all $MUTS mutants killed"; exit 1; }
echo "R5 TESTS GATE PASS"
