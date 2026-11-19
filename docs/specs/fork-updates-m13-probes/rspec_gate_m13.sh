#!/usr/bin/env bash
# Strict rspec gate for milestone fork-updates-m13 (rack 3; redis:8.10-alpine as in docker-compose.yml).
# Starts throwaway postgres+redis on a private docker network, runs the full rspec
# suite in chaskiq-test:m1 against the current tree with RUBYOPT=-W:deprecated.
# Pass = suite booted, 0 failures, 0 errors outside examples, examples >= MIN_EXAMPLES,
# every example of examples_base.txt (the BASE suite, multiset) ran, the rspec process
# exited 0, every pending example is listed in pending_allowed.txt next to this script,
# and the whole container output (boot + suite) has no deprecation or warning line:
# no "deprecat" (any case), no "WARNING: " (rspec false-positive warnings), no Ruby "warning: ".
# Usage (from the repo root; P=docs/specs/fork-updates-m13-probes):
#   bash $P/rspec_gate_m13.sh                 full suite, strict
#   bash $P/rspec_gate_m13.sh --only <file>   one spec file; pass = it ran, 0 failures
#   bash $P/rspec_gate_m13.sh --write-base    COORDINATOR ONLY, on the clean clone before launch:
#        full suite must be green with 0 failures; writes examples_base.txt next to this script.
# MIN_EXAMPLES = number of examples in examples_base.txt.
# Needs: image ${CHASKIQ_TEST_IMAGE:-chaskiq-test:m1}, gems in ${CHASKIQ_M13_BUNDLE:-$HOME/.cache/chaskiq-m13/bundle}.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
MIN_EXAMPLES=$(grep -vc '^#' "$HERE/examples_base.txt" || :)
BUNDLE_DIR=${CHASKIQ_M13_BUNDLE:-$HOME/.cache/chaskiq-m13/bundle}
IMG=${CHASKIQ_TEST_IMAGE:-chaskiq-test:m1}
ID="chqm13-$(printf '%s' "$ROOT" | sha256sum | cut -c1-8)-$$"
cleanup() {
  docker rm -f "$ID-pg" "$ID-redis" >/dev/null 2>&1 || :
  docker network rm "$ID" >/dev/null 2>&1 || :
}
trap cleanup EXIT
mkdir -p tmp "$BUNDLE_DIR"
rm -f tmp/rspec-m13.json tmp/rspec-m13.out tmp/rspec-m13-failures.txt tmp/rspec-m13-pending.txt
docker network create "$ID" >/dev/null
docker run -d --name "$ID-pg" --network "$ID" --network-alias pg \
  -e POSTGRES_PASSWORD=password --tmpfs /var/lib/postgresql/data postgres:14-alpine >/dev/null
docker run -d --name "$ID-redis" --network "$ID" --network-alias redis redis:8.10-alpine >/dev/null
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
  -e HOME=/tmp -e BUNDLE_PATH=/bundle -e RAILS_ENV=test -e RUBYOPT=-W:deprecated \
  -e DATABASE_URL=postgres://postgres:password@pg:5432/chaskiq_test \
  -e REDIS_URL=redis://redis:6379/0 \
  -e M13_TARGET="$TARGET" \
  -v "$BUNDLE_DIR:/bundle" -v "$ROOT:/app" -w /app "$IMG" \
  bash -c 'bundle install --quiet && bin/rails db:create db:schema:load >/dev/null && bundle exec rspec --format progress --format json --out tmp/rspec-m13.json $M13_TARGET' \
  > tmp/rspec-m13.out 2>&1 || rc=$?
tail -5 tmp/rspec-m13.out
echo "rspec container rc=$rc"
test -s tmp/rspec-m13.json || { echo "FAIL: no rspec json (suite did not run)"; tail -40 tmp/rspec-m13.out; exit 1; }
jq -r '.examples[] | select(.status=="failed") | "\(.file_path) :: \(.full_description)"' tmp/rspec-m13.json | LC_ALL=C sort > tmp/rspec-m13-failures.txt
jq -r '.examples[] | select(.status=="pending") | "\(.file_path) :: \(.full_description)"' tmp/rspec-m13.json | LC_ALL=C sort > tmp/rspec-m13-pending.txt
total=$(jq -r '.summary.example_count' tmp/rspec-m13.json)
failed=$(jq -r '.summary.failure_count' tmp/rspec-m13.json)
pending=$(jq -r '.summary.pending_count' tmp/rspec-m13.json)
outside=$(jq -r '.summary.errors_outside_of_examples_count' tmp/rspec-m13.json)
echo "examples=$total failures=$failed pending=$pending errors_outside=$outside"
if [ "$MODE" = "--write-base" ]; then
  [ "$rc" = 0 ] && [ "$failed" = 0 ] && [ "$outside" = 0 ] || { echo "FAIL: suite not green, examples_base.txt not written"; exit 1; }
  { echo "# rspec examples at BASE $(git rev-parse --short HEAD), $total examples, LC_ALL=C sorted"
    jq -r '.examples[] | "\(.file_path) :: \(.full_description)"' tmp/rspec-m13.json | LC_ALL=C sort; } > "$HERE/examples_base.txt"
  echo "WROTE $HERE/examples_base.txt ($total examples)"; exit 0
fi
if [ "$MODE" = "--only" ]; then
  if [ "$rc" = 0 ] && [ "$total" -gt 0 ] && [ "$failed" = 0 ] && [ "$outside" = 0 ]; then echo "PASS: $TARGET"; exit 0; fi
  echo "FAIL: $TARGET"; cat tmp/rspec-m13-failures.txt; exit 1
fi
grep -v '^#' "$HERE/pending_allowed.txt" | LC_ALL=C sort > tmp/rspec-m13-pending-allowed.txt
new_pending=$(LC_ALL=C comm -23 tmp/rspec-m13-pending.txt tmp/rspec-m13-pending-allowed.txt)
jq -r '.examples[] | "\(.file_path) :: \(.full_description)"' tmp/rspec-m13.json | LC_ALL=C sort > tmp/rspec-m13-examples.txt
grep -v '^#' "$HERE/examples_base.txt" | LC_ALL=C sort > tmp/rspec-m13-examples-base.txt
missing=$(LC_ALL=C comm -23 tmp/rspec-m13-examples-base.txt tmp/rspec-m13-examples.txt)
warns=$(grep -naE '[Dd][Ee][Pp][Rr][Ee][Cc][Aa][Tt]|WARNING: |warning: ' tmp/rspec-m13.out | cut -c1-300 || :)
ok=1
if [ "$rc" != 0 ]; then echo "FAIL: rspec process exited $rc"; ok=0; fi
if [ -n "$missing" ]; then echo "FAIL: BASE examples did not run:"; printf '%s\n' "$missing"; ok=0; fi
if [ "$failed" != 0 ]; then echo "FAIL: $failed failures:"; cat tmp/rspec-m13-failures.txt; ok=0; fi
if [ "$outside" != 0 ]; then echo "FAIL: errors outside examples $outside"; ok=0; fi
if [ "$total" -lt "$MIN_EXAMPLES" ]; then echo "FAIL: example count $total < $MIN_EXAMPLES"; ok=0; fi
if [ -n "$new_pending" ]; then echo "FAIL: pending examples not allowed:"; printf '%s\n' "$new_pending"; ok=0; fi
if [ -n "$warns" ]; then echo "FAIL: deprecation/warning lines in the suite output:"; printf '%s\n' "$warns"; ok=0; fi
[ "$ok" = 1 ] && echo "PASS: full suite green, no deprecations" && exit 0
exit 1
