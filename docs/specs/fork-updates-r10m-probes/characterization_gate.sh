#!/usr/bin/env bash
set -euo pipefail
BASE=${1:?Pass the spec commit used as the clone base}
export CI_LOCAL_CACHE=${CHASKIQ_R10M_CACHE:-$HOME/.cache/chaskiq-r10m-ci}
CHAR=$(git rev-list --reverse "$BASE..HEAD" | sed -n '1p')
test -n "$CHAR"
TARGETS='spec/services/message_apis/telegram_r10m_spec.rb spec/services/message_apis/twitter_r10m_spec.rb spec/services/message_apis/twilio_phone_r10m_spec.rb'
mkdir -p tmp
TMP=$(mktemp -d "$PWD/tmp/r10m-characterization.XXXXXX")
trap 'rm -rf -- "$TMP"' EXIT
git clone --shared --no-checkout --quiet . "$TMP/base"
git -C "$TMP/base" checkout --detach --quiet "$CHAR"
for spec_path in $TARGETS; do
  cp "$spec_path" "$TMP/base/$spec_path"
done
CHECKS="--options .rspec --require ./docs/specs/fork-updates-r10m-probes/r10m_sentinel.rb --format progress --format json --out tmp/rspec-r10m-targeted.json $TARGETS"
for tree in "$TMP/base" "$PWD"; do
  (
    cd "$tree"
    mkdir -p tmp
    rm -f tmp/r10m-sentinel.txt tmp/rspec-r10m-targeted.json
    bin/ci-local --only rspec --rspec-args "$CHECKS"
    jq -e '.summary | .example_count > 0 and .failure_count == 0 and .pending_count == 0 and .errors_outside_of_examples_count == 0' tmp/rspec-r10m-targeted.json >/dev/null
    test "$(wc -l < tmp/r10m-sentinel.txt)" -eq "$(jq .summary.example_count tmp/rspec-r10m-targeted.json)"
    jq -e '[.examples[].file_path] | unique | length == 3' tmp/rspec-r10m-targeted.json >/dev/null
  )
done
echo 'R10M CHARACTERIZATION PASS'
