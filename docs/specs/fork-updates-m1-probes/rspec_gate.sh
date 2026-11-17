#!/usr/bin/env bash
# Rspec gate for milestone fork-updates-m1.
# Starts throwaway postgres+redis on a private docker network, runs the full rspec
# suite in chaskiq-test:m1 against the current tree, and compares failures with
# rspec_baseline.txt next to this script (failures recorded on main + minimal globalize/roadie fix).
# Pass = suite booted, examples >= baseline count, and no failure outside the baseline.
# Usage (from the repo root; P=docs/specs/fork-updates-m1-probes):
#   bash $P/rspec_gate.sh                 full suite, compare with baseline
#   bash $P/rspec_gate.sh --record        full suite, write tmp/rspec-m1-failures.txt only
#   bash $P/rspec_gate.sh --only <file>   run one spec file; pass = it ran and has 0 failures
# Needs: image chaskiq-test:m1 (Dockerfile.test here), gems in $HOME/.cache/chaskiq-m1/bundle.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
BUNDLE_DIR=${CHASKIQ_M1_BUNDLE:-$HOME/.cache/chaskiq-m1/bundle}
IMG=chaskiq-test:m1
ID="chqm1-$(printf '%s' "$ROOT" | sha256sum | cut -c1-8)-$$"
cleanup() {
  docker rm -f "$ID-pg" "$ID-redis" >/dev/null 2>&1 || :
  docker network rm "$ID" >/dev/null 2>&1 || :
}
trap cleanup EXIT
mkdir -p tmp "$BUNDLE_DIR"
rm -f tmp/rspec-m1.json tmp/rspec-m1-failures.txt
docker network create "$ID" >/dev/null
docker run -d --name "$ID-pg" --network "$ID" --network-alias pg \
  -e POSTGRES_PASSWORD=password --tmpfs /var/lib/postgresql/data postgres:14-alpine >/dev/null
docker run -d --name "$ID-redis" --network "$ID" --network-alias redis redis:5-alpine >/dev/null
for _ in $(seq 1 60); do
  docker exec "$ID-pg" pg_isready -U postgres -h 127.0.0.1 >/dev/null 2>&1 && break
  sleep 1
done
docker exec "$ID-pg" pg_isready -U postgres -h 127.0.0.1 >/dev/null
MODE=${1:-}
TARGET=""
if [ "$MODE" = "--only" ]; then
  TARGET=${2:?--only needs a spec file}
  test -f "$TARGET" || { echo "FAIL: $TARGET missing"; exit 1; }
fi
rc=0
docker run --rm --network "$ID" --user "$(id -u):$(id -g)" \
  -e HOME=/tmp -e BUNDLE_PATH=/bundle -e RAILS_ENV=test \
  -e DATABASE_URL=postgres://postgres:password@pg:5432/chaskiq_test \
  -e REDIS_URL=redis://redis:6379/0 \
  -e M1_TARGET="$TARGET" \
  -v "$BUNDLE_DIR:/bundle" -v "$ROOT:/app" -w /app "$IMG" \
  bash -c 'bundle install --quiet && bin/rails db:create db:schema:load >/dev/null && bundle exec rspec --format progress --format json --out tmp/rspec-m1.json $M1_TARGET' || rc=$?
echo "rspec container rc=$rc"
test -s tmp/rspec-m1.json || { echo "FAIL: no rspec json (suite did not run)"; exit 1; }
jq -r '.examples[] | select(.status=="failed") | "\(.file_path) :: \(.full_description)"' tmp/rspec-m1.json | LC_ALL=C sort > tmp/rspec-m1-failures.txt
total=$(jq -r '.summary.example_count' tmp/rspec-m1.json)
failed=$(jq -r '.summary.failure_count' tmp/rspec-m1.json)
pending=$(jq -r '.summary.pending_count' tmp/rspec-m1.json)
outside=$(jq -r '.summary.errors_outside_of_examples_count' tmp/rspec-m1.json)
echo "examples=$total failures=$failed pending=$pending errors_outside=$outside"
if [ "$MODE" = "--record" ]; then exit 0; fi
if [ "$MODE" = "--only" ]; then
  if [ "$total" -gt 0 ] && [ "$failed" = 0 ] && [ "$outside" = 0 ]; then echo "PASS: $TARGET"; exit 0; fi
  echo "FAIL: $TARGET"; cat tmp/rspec-m1-failures.txt; exit 1
fi
base="$HERE/rspec_baseline.txt"
base_total=$(sed -n 's/^# examples=\([0-9]*\).*/\1/p' "$base")
base_outside=$(sed -n 's/^# examples=.* errors_outside=\([0-9]*\).*/\1/p' "$base")
grep -v '^#' "$base" | LC_ALL=C sort > tmp/rspec-m1-baseline-sorted.txt
new=$(LC_ALL=C comm -23 tmp/rspec-m1-failures.txt tmp/rspec-m1-baseline-sorted.txt)
fixed=$(LC_ALL=C comm -13 tmp/rspec-m1-failures.txt tmp/rspec-m1-baseline-sorted.txt | wc -l)
echo "baseline examples=$base_total; baseline failures now passing=$fixed"
ok=1
if [ "$total" -lt "$base_total" ]; then echo "FAIL: example count $total < baseline $base_total"; ok=0; fi
if [ "$outside" -gt "$base_outside" ]; then echo "FAIL: errors outside examples $outside > baseline $base_outside"; ok=0; fi
if [ -n "$new" ]; then echo "FAIL: new failures not in baseline:"; printf '%s\n' "$new"; ok=0; fi
[ "$ok" = 1 ] && echo "PASS: no new failures" && exit 0
exit 1
