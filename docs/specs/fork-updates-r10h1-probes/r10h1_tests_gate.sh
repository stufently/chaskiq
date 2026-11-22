#!/usr/bin/env bash
# Test gate for fork-updates-r10h1: golden fixture = BASE output of the coordinator's generator (r10h1_golden_spec.rb over r10h1_cases.json); characterization examples green on BASE and the tree, "renamed" examples
# (mixed_specs) and fix specs red on BASE and green on the tree, every mutant of r10h1_config.json killed
# (r10h1_tests.rb).
#
#   CHASKIQ_R10H_CACHE=~/.cache/chaskiq-r10h-ci bash r10h1_tests_gate.sh <BASE_SHA>
#
# Works on a copy: HEAD via git archive to tmp/r10h1-tests/tree, BASE versions of the patched files to
# tmp/r10h1-tests/base (new_files are removed for the BASE run); runs in the bin/ci-local image with postgres/redis as in `bin/ci-local --only
# rspec`. Pass = "R10H1 TREE PASS", "R10H1 BASE PASS", "R10H1 MUTANTS PASS k/k killed", "R10H1 GOLDEN PASS n cases" with k = mutants in
# r10h1_config.json, exit 0.
set -euo pipefail
BASE=${1:?usage: r10h1_tests_gate.sh <BASE_SHA>}
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
CACHE=${CHASKIQ_R10H_CACHE:-$HOME/.cache/chaskiq-r10h-ci}
IMG="chaskiq-ci-local:ruby-$(tr -d '[:space:]' < .ruby-version)-ubuntu-26.04"
docker image inspect "$IMG" >/dev/null 2>&1 || { echo "FAIL: image $IMG missing (built by bin/ci-local)"; exit 1; }
test -d "$CACHE/bundle-ubuntu-26.04" || { echo "FAIL: gem cache $CACHE/bundle-ubuntu-26.04 missing"; exit 1; }
W=tmp/r10h1-tests
rm -rf "$W"
mkdir -p "$W/tree" "$W/base" "$W/out" vendor/bundle
git archive HEAD | tar -x -C "$W/tree"
jq -r '.app_files[]' "$HERE/r10h1_config.json" > "$W/app_files"
while IFS= read -r f; do
  mkdir -p "$W/base/$(dirname "$f")"
  git show "$BASE:$f" > "$W/base/$f"
done < "$W/app_files"
# CI=1 makes the test environment eager-load (config/environments/test.rb), as on GitHub Actions.
EAGER=$(jq -r 'if .eager then "1" else "" end' "$HERE/r10h1_config.json")
cp "$HERE/r10h1_config.json" "$HERE/r10h1_tests.rb" "$W/"
cp "$HERE/r10h1_golden_spec.rb" "$HERE/r10h1_cases.json" "$W/"
MUTS=$(jq '.mutants | length' "$HERE/r10h1_config.json")
ID="r10h1tests-$$-$(date +%s)"
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
  -e BUNDLE_BUILD__SCOUT_APM="--with-cflags=-std=gnu17" -e RAILS_ENV=test ${EAGER:+-e CI=1} \
  -e DATABASE_URL=postgres://postgres:postgres@pg:5432/test -e REDIS_URL=redis://redis:6379/0 \
  -v "$ROOT:/app" -v "$CACHE/bundle-ubuntu-26.04:/bundle" -w "/app/$W/tree" "$IMG" bash -c '
    set -e
    bundle install --quiet
    bin/rails db:prepare >/dev/null
    ruby ../r10h1_tests.rb ../r10h1_config.json ../base ../out' > "$W/out.txt" 2>&1 || rc=$?
grep -E '^(R10H1 |KILLED|FAIL)' "$W/out.txt" | head -60 || :
[ "$rc" = 0 ] || { echo "FAIL: run exited $rc"; tail -20 "$W/out.txt"; exit 1; }
grep -qE '^R10H1 TREE PASS [1-9][0-9]* examples$' "$W/out.txt" || { echo "FAIL: no tree verdict"; exit 1; }
grep -qE '^R10H1 BASE PASS [0-9]+ char / [0-9]+ renamed failing / [0-9]+ fix failing$' "$W/out.txt" || { echo "FAIL: no BASE verdict"; exit 1; }
grep -qx "R10H1 MUTANTS PASS $MUTS/$MUTS killed" "$W/out.txt" || { echo "FAIL: not all $MUTS mutants killed"; exit 1; }
NCASES=$(jq length "$HERE/r10h1_cases.json")
grep -qx "R10H1 GOLDEN PASS $NCASES cases" "$W/out.txt" || { echo "FAIL: golden fixture is not the BASE output of all $NCASES cases"; exit 1; }
echo "R10H1 TESTS GATE PASS"
