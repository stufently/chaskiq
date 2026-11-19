#!/usr/bin/env bash
# Proof that the milestone's new tests are regression tests: they FAIL on BASE.
# Usage (clone root): bash docs/specs/fork-updates-m9-probes/m9_red_on_base.sh <BASE_SHA>
# Makes a throwaway checkout of BASE in tmp/m9-red-base, copies every spec file that HEAD added
# or changed (BASE...HEAD, *_spec.rb under spec/) into it, runs exactly those files there and
# passes only when:
#   - the suite loaded (0 errors outside examples) and at least one example failed;
#   - every failure is a NEW example (its "file :: full description" is not in examples_base.txt);
#   - each required file has a failed example whose full description matches its marker:
#       block_manager_spec  /on_success/, /on_failure/, /returned/, /already_sent/
#       telegram, vonage, message_bird, twilio, dialog_360 hook specs  /partial failure/
#       vonage  /provider id/, /immediately/, /resume/
#       dialog_360  /provider id/, /empty/, /failed status event/
#       twilio  /safe/, /status callback/
#   - examples marked "base-green" in their description are legitimately green on BASE (the old
#     code already behaves so): none of them may fail there, and these must exist and pass:
#       twilio /once/, /separate text/, /single text/;  vonage /retry/
# Needs: image chaskiq-test:m1, gems in $HOME/.cache/chaskiq-m6/bundle, postgres:14-alpine, redis:8.10-alpine.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
B=${1:?usage: m9_red_on_base.sh <BASE_SHA>}
BUNDLE_DIR=${CHASKIQ_BUNDLE:-$HOME/.cache/chaskiq-m6/bundle}
IMG=chaskiq-test:m1
W=tmp/m9-red-base
ID="chqm9r-$(printf '%s' "$ROOT" | sha256sum | cut -c1-8)-$$"
cleanup() {
  docker rm -f "$ID-pg" "$ID-redis" >/dev/null 2>&1 || :
  docker network rm "$ID" >/dev/null 2>&1 || :
  rm -rf "$W"
}
trap cleanup EXIT
mapfile -t FILES < <(git diff --name-only --diff-filter=AM "$B" HEAD -- spec | grep -E '_spec[.]rb$' | grep -v '^spec/support/' || :)
if [ "${#FILES[@]}" = 0 ]; then echo "FAIL: HEAD adds or changes no spec file over BASE"; exit 1; fi
rm -rf "$W"
mkdir -p tmp
git clone -q --shared --no-checkout . "$W"
git -C "$W" checkout -q --detach "$B"
for f in "${FILES[@]}"; do
  mkdir -p "$W/$(dirname "$f")"
  git show "HEAD:$f" > "$W/$f"
done
printf 'spec files from HEAD on BASE %s:\n' "$(git rev-parse --short "$B")"; printf '  %s\n' "${FILES[@]}"
docker network create "$ID" >/dev/null
docker run -d --name "$ID-pg" --network "$ID" --network-alias pg \
  -e POSTGRES_PASSWORD=password --tmpfs /var/lib/postgresql/data postgres:14-alpine >/dev/null
docker run -d --name "$ID-redis" --network "$ID" --network-alias redis redis:8.10-alpine >/dev/null
for _ in $(seq 1 60); do
  docker exec "$ID-pg" pg_isready -U postgres -h 127.0.0.1 >/dev/null 2>&1 && break
  sleep 1
done
docker exec "$ID-pg" pg_isready -U postgres -h 127.0.0.1 >/dev/null
mkdir -p "$W/tmp"
rc=0
docker run --rm --network "$ID" --user "$(id -u):$(id -g)" \
  -e HOME=/tmp -e BUNDLE_PATH=/bundle -e RAILS_ENV=test \
  -e DATABASE_URL=postgres://postgres:password@pg:5432/chaskiq_test \
  -e REDIS_URL=redis://redis:6379/0 \
  -v "$BUNDLE_DIR:/bundle" -v "$ROOT/$W:/app" -w /app "$IMG" \
  bash -c 'bundle install --quiet && bin/rails db:create db:schema:load >/dev/null && bundle exec rspec --format progress --format json --out tmp/red.json "$@"' _ "${FILES[@]}" || rc=$?
J="$W/tmp/red.json"
test -s "$J" || { echo "FAIL: no rspec json (suite did not run)"; exit 1; }
outside=$(jq -r '.summary.errors_outside_of_examples_count' "$J")
failed=$(jq -r '.summary.failure_count' "$J")
echo "rspec rc=$rc examples=$(jq -r '.summary.example_count' "$J") failures=$failed errors_outside=$outside"
ok=1
if [ "$outside" != 0 ]; then echo "FAIL: errors outside examples on BASE ($outside): the new tests must load on BASE and fail as examples"; ok=0; fi
if [ "$failed" = 0 ]; then echo "FAIL: nothing fails on BASE"; ok=0; fi
grep -v '^#' "$HERE/examples_base.txt" | LC_ALL=C sort -u > "$W/tmp/base-examples.txt"
jq -r '.examples[] | select(.status=="failed") | "\(.file_path) :: \(.full_description)"' "$J" | LC_ALL=C sort -u > "$W/tmp/red-failed.txt"
old=$(LC_ALL=C comm -12 "$W/tmp/base-examples.txt" "$W/tmp/red-failed.txt")
if [ -n "$old" ]; then echo "FAIL: examples that exist at BASE fail on BASE:"; printf '%s\n' "$old"; ok=0; fi
need() {
  local file=$1 marker=$2
  if ! jq -e --arg f "./$file" --arg m "$marker" \
      '[.examples[] | select(.status=="failed" and .file_path==$f and (.full_description | test($m; "i")))] | length > 0' "$J" >/dev/null; then
    echo "FAIL: no failing example matching /$marker/ in $file on BASE"; ok=0
  else
    echo "red on BASE: $file /$marker/"
  fi
}
H=spec/controllers/api/v1/hooks
for m in on_success on_failure returned already_sent; do need spec/services/message_apis/block_manager_spec.rb "$m"; done
for p in telegram vonage message_bird twilio dialog_360; do need "$H/${p}_spec.rb" "partial failure"; done
for m in "provider id" immediately resume; do need "$H/vonage_spec.rb" "$m"; done
for m in "provider id" empty "failed status event"; do need "$H/dialog_360_spec.rb" "$m"; done
for m in safe "status callback"; do need "$H/twilio_spec.rb" "$m"; done
bad_green=$(jq -r '.examples[] | select(.status=="failed" and (.full_description | test("base-green"; "i"))) | "\(.file_path) :: \(.full_description)"' "$J")
if [ -n "$bad_green" ]; then echo "FAIL: base-green examples fail on BASE:"; printf '%s\n' "$bad_green"; ok=0; fi
green() {
  local file=$1 marker=$2
  if jq -e --arg f "./$file" --arg m "$marker" \
      '[.examples[] | select(.status=="passed" and .file_path==$f and (.full_description | test("base-green"; "i")) and (.full_description | test($m; "i")))] | length > 0' "$J" >/dev/null; then
    echo "green on BASE as declared: $file /$marker/ base-green"
  else
    echo "FAIL: no passing base-green example matching /$marker/ in $file on BASE"; ok=0
  fi
}
for m in once "separate text" "single text"; do green "$H/twilio_spec.rb" "$m"; done
green "$H/vonage_spec.rb" retry
[ "$ok" = 1 ] && echo "M9 RED ON BASE PASS" && exit 0
exit 1
