#!/usr/bin/env bash
# fork-updates-m10: the milestone's new tests are regression tests — checked PER EXAMPLE on BASE.
# Usage (clone root): bash docs/specs/fork-updates-m10-probes/m10_red_on_base.sh <BASE_SHA>
# A throwaway checkout of BASE in tmp/m10-red-base gets the spec files below copied from HEAD; they run
# there in one rspec process. Pass only when:
#   - the files load on BASE (0 errors outside examples: a load error is NOT red);
#   - every NEW example (its "file :: full description" is not in examples_base.txt) FAILS on BASE,
#     except examples whose description contains "base-green" — those must PASS on BASE;
#   - no example that exists at BASE (examples_base.txt) fails;
#   - each file has a failing example matching each of its markers (need_markers below, = spec 5.C).
# Needs: image chaskiq-test:m1, gems in $HOME/.cache/chaskiq-m6/bundle, postgres:14-alpine, redis:8.10-alpine.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
B=${1:?usage: m10_red_on_base.sh <BASE_SHA>}
BUNDLE_DIR=${CHASKIQ_M6_BUNDLE:-$HOME/.cache/chaskiq-m6/bundle}
IMG=chaskiq-test:m1
W=tmp/m10-red-base
ID="chqm10r-$(printf '%s' "$ROOT" | sha256sum | cut -c1-8)-$$"
FILES=(
  spec/services/message_apis/sns_message_verifier_spec.rb
  spec/controllers/api/v1/hooks_sns_signature_spec.rb
)
need_markers() {
  need spec/services/message_apis/sns_message_verifier_spec.rb "Subject"
  need spec/services/message_apis/sns_message_verifier_spec.rb "newline"
  need spec/services/message_apis/sns_message_verifier_spec.rb "SignatureVersion"
  need spec/services/message_apis/sns_message_verifier_spec.rb "SigningCertURL"
  need spec/services/message_apis/sns_message_verifier_spec.rb "redirect"
  need spec/services/message_apis/sns_message_verifier_spec.rb "64 KiB"
  need spec/services/message_apis/sns_message_verifier_spec.rb "5 seconds"
  need spec/services/message_apis/sns_message_verifier_spec.rb "cache"
  need spec/services/message_apis/sns_message_verifier_spec.rb "temporary"
  need spec/services/message_apis/sns_message_verifier_spec.rb "TopicArn"
  need spec/services/message_apis/sns_message_verifier_spec.rb "Base64"
  need spec/services/message_apis/sns_message_verifier_spec.rb "required"
  need spec/services/message_apis/sns_message_verifier_spec.rb "not_after"
  need spec/controllers/api/v1/hooks_sns_signature_spec.rb "unsigned"
  need spec/controllers/api/v1/hooks_sns_signature_spec.rb "tampered"
  need spec/controllers/api/v1/hooks_sns_signature_spec.rb "header"
  need spec/controllers/api/v1/hooks_sns_signature_spec.rb "503"
}
cleanup() {
  docker rm -f "$ID-pg" "$ID-redis" >/dev/null 2>&1 || :
  docker network rm "$ID" >/dev/null 2>&1 || :
  rm -rf "$W"
}
trap cleanup EXIT
for f in "${FILES[@]}"; do
  git cat-file -e "HEAD:$f" 2>/dev/null || { echo "FAIL: $f is not committed at HEAD"; exit 1; }
done
rm -rf "$W"
mkdir -p tmp
git clone -q --shared --no-checkout . "$W"
git -C "$W" checkout -q --detach "$B"
for f in "${FILES[@]}"; do
  mkdir -p "$W/$(dirname "$f")"
  git show "HEAD:$f" > "$W/$f"
done
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
echo "rspec rc=$rc examples=$(jq -r '.summary.example_count' "$J") failures=$(jq -r '.summary.failure_count' "$J") errors_outside=$outside"
ok=1
if [ "$outside" != 0 ]; then echo "FAIL: errors outside examples on BASE ($outside): the new tests must load on BASE"; ok=0; fi
grep -v '^#' "$HERE/examples_base.txt" | LC_ALL=C sort -u > "$W/tmp/base.txt"
jq -r '.examples[] | "\(.status)\t\(.file_path) :: \(.full_description)"' "$J" > "$W/tmp/all.tsv"
while IFS=$'\t' read -r status name; do
  if grep -qxF "$name" "$W/tmp/base.txt"; then
    [ "$status" = failed ] && { echo "FAIL: BASE example fails on BASE: $name"; ok=0; }
  elif printf '%s' "$name" | grep -qi 'base-green'; then
    [ "$status" = passed ] || { echo "FAIL: base-green example is $status on BASE: $name"; ok=0; }
  else
    [ "$status" = failed ] || { echo "FAIL: new example is $status on BASE (must fail or be marked base-green): $name"; ok=0; }
  fi
done < "$W/tmp/all.tsv"
need() {
  local file=$1 marker=$2
  if jq -e --arg f "./$file" --arg m "$marker" \
      '[.examples[] | select(.status=="failed" and .file_path==$f and (.full_description | test($m; "i")))] | length > 0' "$J" >/dev/null; then
    echo "red on BASE: $file /$marker/"
  else
    echo "FAIL: no failing example matching /$marker/ in $file on BASE"; ok=0
  fi
}
need_markers
[ "$ok" = 1 ] && echo "M10 RED ON BASE PASS" && exit 0
exit 1
