#!/usr/bin/env bash
# Test gate for fork-updates-r9b: characterization examples green on BASE and the tree, "renamed" examples
# (mixed_specs) and fix specs red on BASE and green on the tree, every mutant of r9b_config.json killed
# (r9b_tests.rb); and the files of iseq_same.patch compile, after that patch alone on BASE, to the same
# YARV bytecode as at BASE (r9b_iseq.rb: line numbers ignored; "R9B ISEQ PASS <n> files").
#
#   CHASKIQ_R9B_CACHE=~/.cache/chaskiq-r9b-ci bash r9b_tests_gate.sh <BASE_SHA>
#
# Works on a copy: HEAD via git archive to tmp/r9b-tests/tree, BASE versions of the patched files to
# tmp/r9b-tests/base (new_files are removed for the BASE run); runs in the bin/ci-local image with postgres/redis as in `bin/ci-local --only
# rspec`. Pass = "R9B TREE PASS", "R9B BASE PASS", "R9B MUTANTS PASS k/k killed" with k = mutants in
# r9b_config.json, "R9B ISEQ PASS n files", exit 0.
set -euo pipefail
BASE=${1:?usage: r9b_tests_gate.sh <BASE_SHA>}
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
CACHE=${CHASKIQ_R9B_CACHE:-$HOME/.cache/chaskiq-r9b-ci}
IMG="chaskiq-ci-local:ruby-$(tr -d '[:space:]' < .ruby-version)-ubuntu-26.04"
docker image inspect "$IMG" >/dev/null 2>&1 || { echo "FAIL: image $IMG missing (built by bin/ci-local)"; exit 1; }
test -d "$CACHE/bundle-ubuntu-26.04" || { echo "FAIL: gem cache $CACHE/bundle-ubuntu-26.04 missing"; exit 1; }
W=tmp/r9b-tests
rm -rf "$W"
mkdir -p "$W/tree" "$W/base" "$W/out" vendor/bundle
git archive HEAD | tar -x -C "$W/tree"
jq -r '.app_files[]' "$HERE/r9b_config.json" > "$W/app_files"
while IFS= read -r f; do
  mkdir -p "$W/base/$(dirname "$f")"
  git show "$BASE:$f" > "$W/base/$f"
done < "$W/app_files"
# iseq_same: BASE versions of its files with only its patch applied (the modifier-form rewrite).
jq -r '.iseq_same.files[]' "$HERE/r9b_config.json" > "$W/iseq_files"
mkdir -p "$W/stage"
while IFS= read -r f; do
  mkdir -p "$W/stage/$(dirname "$f")"
  git show "$BASE:$f" > "$W/stage/$f"
done < "$W/iseq_files"
# tmp/ is inside the work tree: stop git from finding the repo, or `git apply` would skip the paths.
(cd "$W/stage" && GIT_CEILING_DIRECTORIES="$ROOT/tmp" git apply "$HERE/$(jq -r '.iseq_same.patch' "$HERE/r9b_config.json")") \
  || { echo "FAIL: iseq_same patch does not apply to BASE"; exit 1; }
NISEQ=$(grep -c . "$W/iseq_files")
[ "$NISEQ" -gt 0 ] || { echo "FAIL: iseq_same lists no files"; exit 1; }
cp "$HERE/r9b_iseq.rb" "$W/"
# CI=1 makes the test environment eager-load (config/environments/test.rb), as on GitHub Actions.
EAGER=$(jq -r 'if .eager then "1" else "" end' "$HERE/r9b_config.json")
cp "$HERE/r9b_config.json" "$HERE/r9b_tests.rb" "$W/"
MUTS=$(jq '.mutants | length' "$HERE/r9b_config.json")
ID="r9btests-$$-$(date +%s)"
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
    mapfile -t isf < ../iseq_files
    ruby ../r9b_iseq.rb ../base ../stage "${isf[@]}" > ../iseq.txt 2>&1
    bin/rails db:prepare >/dev/null
    ruby ../r9b_tests.rb ../r9b_config.json ../base ../out' > "$W/out.txt" 2>&1 || rc=$?
grep -E '^(R9B |KILLED|FAIL)' "$W/out.txt" | head -60 || :
cat "$W/iseq.txt" 2>/dev/null || :
[ "$rc" = 0 ] || { echo "FAIL: run exited $rc"; tail -20 "$W/out.txt"; exit 1; }
grep -qE '^R9B TREE PASS [1-9][0-9]* examples$' "$W/out.txt" || { echo "FAIL: no tree verdict"; exit 1; }
grep -qE '^R9B BASE PASS [0-9]+ char / [0-9]+ renamed failing / [0-9]+ fix failing$' "$W/out.txt" || { echo "FAIL: no BASE verdict"; exit 1; }
grep -qx "R9B MUTANTS PASS $MUTS/$MUTS killed" "$W/out.txt" || { echo "FAIL: not all $MUTS mutants killed"; exit 1; }
same=$(grep -cE '^SAME ' "$W/iseq.txt" || [ $? -eq 1 ])
other=$(grep -cvE '^SAME ' "$W/iseq.txt" || [ $? -eq 1 ])
[ "$same" = "$NISEQ" ] && [ "$other" = 0 ] \
  || { echo "FAIL: iseq_same: $same of $NISEQ files have BASE bytecode, $other other lines (above)"; exit 1; }
echo "R9B ISEQ PASS $NISEQ files"
echo "R9B TESTS GATE PASS"
