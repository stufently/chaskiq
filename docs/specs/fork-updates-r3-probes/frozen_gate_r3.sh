#!/usr/bin/env bash
# Runtime literal-mutation gate for fork-updates-r3 (`# frozen_string_literal: true`).
#
#   bash frozen_gate_r3.sh                         the gate (tree): see "Pass" below
#   bash frozen_gate_r3.sh --raw <out> <RUBYOPT> [rspec args]   only run, write the output, exit rspec's rc
#
# Runs, with RUBYOPT="--enable-frozen-string-literal --debug-frozen-string-literal -W:deprecated", the
# same steps as `bin/ci-local --only rspec` (postgres:14-alpine, redis:8.10-alpine, bundle install,
# yarn install, db:prepare; bin/ci-local cannot pass RUBYOPT), plus, before rspec, an eager load of
# the app and of every rake file (code the suite never loads). --enable-frozen-string-literal freezes
# EVERY literal - the files of R3, the rest of the app, gems, ERB/eval code - so any mutation of a
# literal on a path the run takes raises FrozenError, and --debug-frozen-string-literal names the
# line that created the literal; -W:deprecated keeps the chilled-literal warning visible should a
# literal escape the flag.
# Pass = eager load printed "R3 EAGER LOAD OK"; rspec exited 0 with 0 failures and at least as many
# examples as examples_base.txt; the output has no FrozenError, no "can't modify frozen String" and no
# chilled-literal warning at all. BASE (measured): the same run is green with none of them, and the
# run without --enable-frozen-string-literal (chilled literals, warnings on) prints no chilled-literal
# warning either.
# Cache: ${CHASKIQ_R3_CACHE:-$HOME/.cache/chaskiq-r3-ci}.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
CACHE=${CHASKIQ_R3_CACHE:-$HOME/.cache/chaskiq-r3-ci}
IMG="chaskiq-ci-local:ruby-$(tr -d '[:space:]' < .ruby-version)-ubuntu-26.04"
OPT="--enable-frozen-string-literal --debug-frozen-string-literal -W:deprecated"
OUT=tmp/rspec-r3-frozen.out
ARGS=""
RAW=""
if [ "${1:-}" = "--raw" ]; then
  RAW=1; OUT=${2:?--raw needs <out>}; OPT=${3:?--raw needs <RUBYOPT>}; ARGS=${4:-}
fi
docker image inspect "$IMG" >/dev/null 2>&1 || { echo "FAIL: image $IMG missing (built by bin/ci-local)"; exit 1; }
# A hidden --dry-run in .rspec-local / ~/.rspec / SPEC_OPTS would pass without running bodies:
# refuse them, read only the committed .rspec (container HOME is a fresh /tmp, SPEC_OPTS is not
# passed in), and count the bodies that ran (r3_sentinel.rb).
[ -z "${SPEC_OPTS:-}" ] || { echo "FAIL: SPEC_OPTS is set"; exit 1; }
for f in .rspec-local .rspec-parallel; do [ ! -e "$f" ] || { echo "FAIL: $f present (rspec would read it)"; exit 1; }; done
SENT=tmp/r3-sentinel-frozen.txt
rm -f "$SENT"
if [ -z "$RAW" ]; then
  min=$(grep -v '^#' "$HERE/examples_base.txt" | grep -c .) || { echo "FAIL: examples_base.txt missing or empty"; exit 1; }
fi
ID="r3frozen-$$-$(date +%s)"
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
mkdir -p "$CACHE/bundle-ubuntu-26.04" "$CACHE/yarn" vendor/bundle tmp "$(dirname "$OUT")"
rc=0
docker run --rm --init --user "$(id -u):$(id -g)" --network "$ID" \
  -e HOME=/tmp -e BUNDLE_PATH=/app/vendor/bundle -e BUNDLE_FROZEN=true -e YARN_CACHE_FOLDER=/yarn \
  -e BUNDLE_BUILD__SCOUT_APM="--with-cflags=-std=gnu17" -e RAILS_ENV=test \
  -e DATABASE_URL=postgres://postgres:postgres@pg:5432/test -e REDIS_URL=redis://redis:6379/0 \
  -e R3_RUBYOPT="$OPT" -e R3_ARGS="$ARGS" -e R3_SENTINEL="$SENT" \
  -v "$ROOT:/app" -v "$CACHE/bundle-ubuntu-26.04:/app/vendor/bundle" -v "$CACHE/yarn:/yarn" -w /app \
  "$IMG" bash -c '
    set -e
    bundle install --quiet
    yarn install --frozen-lockfile --non-interactive --silent
    bin/rails db:prepare >/dev/null
    RUBYOPT="$R3_RUBYOPT" bin/rails runner "Rails.application.eager_load!; Rails.application.load_tasks; puts %q(R3 EAGER LOAD OK)"
    RUBYOPT="$R3_RUBYOPT" bundle exec rspec --options .rspec --require ./docs/specs/fork-updates-r3-probes/r3_sentinel.rb --format progress $R3_ARGS' > "$OUT" 2>&1 || rc=$?
echo "run rc=$rc"
[ -n "$RAW" ] && exit "$rc"
grep -aE '^[0-9]+ examples?, ' "$OUT" | tail -1
ok=1
[ "$rc" = 0 ] || { echo "FAIL: run exited $rc"; tail -30 "$OUT"; ok=0; }
grep -qx 'R3 EAGER LOAD OK' "$OUT" || { echo "FAIL: eager load did not finish"; ok=0; }
summary=$(grep -aE '^[0-9]+ examples?, [0-9]+ failures?' "$OUT" | tail -1 || [ $? -eq 1 ])
total=$(printf '%s' "$summary" | sed -nE 's/^([0-9]+) examples?.*/\1/p')
failed=$(printf '%s' "$summary" | sed -nE 's/^[0-9]+ examples?, ([0-9]+) failures?.*/\1/p')
[ -n "$total" ] && [ "$total" -ge "$min" ] || { echo "FAIL: examples ${total:-none} < $min (examples_base.txt)"; ok=0; }
[ "${failed:-x}" = 0 ] || { echo "FAIL: failures ${failed:-unknown}"; ok=0; }
pend=$(printf '%s' "$summary" | sed -nE 's/.* ([0-9]+) pending.*/\1/p')
ran=$( (cat "$SENT" 2>/dev/null || :) | grep -c . || :)
echo "bodies run (sentinel)=${ran:-0}"
[ -n "$total" ] && [ "${ran:-0}" -ge $((total - ${pend:-0})) ] && [ "${ran:-0}" -gt 0 ] \
  || { echo "FAIL: only ${ran:-0} example bodies ran of ${total:-?} examples: dry run or hooks skipped"; ok=0; }
hits=$(grep -anE 'literal string will be frozen|the string was created here|FrozenError|can.t modify frozen String' "$OUT" \
  || [ $? -eq 1 ])
[ -z "$hits" ] || { echo "FAIL: literal mutated at run time:"; printf '%s\n' "$hits" | head -40; ok=0; }
[ "$ok" = 1 ] && echo "R3 FROZEN PASS" && exit 0
exit 1
