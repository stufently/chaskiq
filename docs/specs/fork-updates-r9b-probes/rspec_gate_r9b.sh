#!/usr/bin/env bash
# Strict rspec gate for milestone fork-updates-r9b (RuboCop backlog, R9b: remaining one-off Style cops).
# Runs the full suite through bin/ci-local (the CI-parity runner: ubuntu-26.04 image, Ruby of
# .ruby-version, postgres/redis of the workflows), with its own gem/yarn cache, and adds a JSON
# report so the example list can be compared with BASE.
# Pass = rspec exited 0, 0 failures, 0 errors outside examples, examples >= MIN_EXAMPLES, every
# example of examples_base.txt (the BASE suite, multiset) ran, every pending example is listed in
# pending_allowed.txt, and the suite output has no line that BASE did not print
# (deprecation / "warning: " / "WARNING: " lines are compared against warnings_base.txt).
# Usage (from the repo root; P=docs/specs/fork-updates-r9b-probes):
#   bash $P/rspec_gate_r9b.sh                 full suite, strict
#   bash $P/rspec_gate_r9b.sh --only <file>   one spec file; pass = it ran, 0 failures
#   bash $P/rspec_gate_r9b.sh --write-base    COORDINATOR ONLY, on a clean checkout of BASE: the suite
#        must be green; writes examples_base.txt, pending_allowed.txt and warnings_base.txt here.
# Cache: ${CHASKIQ_R9B_CACHE:-$HOME/.cache/chaskiq-r9b-ci} (CI_LOCAL_CACHE of bin/ci-local; not shared
# with the pre-push hook of the live tree).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
export CI_LOCAL_CACHE=${CHASKIQ_R9B_CACHE:-$HOME/.cache/chaskiq-r9b-ci}
# grep exits 1 on "no lines" (a snapshot file with only its header): that is an empty set, not an
# error, under set -euo pipefail. Exit 2 (missing file) still aborts.
data_lines() { grep -v '^#' "$1" || [ $? -eq 1 ]; }
MIN_EXAMPLES=$(data_lines "$HERE/examples_base.txt" | grep -c . || [ $? -eq 1 ])
MODE=${1:-}
TARGET=""
if [ "$MODE" = "--only" ]; then
  TARGET=${2:?--only needs a spec file}
  test -f "$TARGET" || { echo "FAIL: $TARGET missing"; exit 1; }
fi
# RSpec also reads .rspec-local, ~/.rspec and SPEC_OPTS: a hidden `--dry-run` there would pass the
# gate without running a single body. Refuse them, read only the committed .rspec (`--options .rspec`
# replaces the global, project and local files; HOME in the container is a fresh /tmp), and count the
# examples whose body ran (r9b_sentinel.rb, after hook; dry-run runs no hooks).
[ -z "${SPEC_OPTS:-}" ] || { echo "FAIL: SPEC_OPTS is set"; exit 1; }
for f in .rspec-local .rspec-parallel; do [ ! -e "$f" ] || { echo "FAIL: $f present (rspec would read it)"; exit 1; }; done
mkdir -p tmp
SENT=tmp/r9b-sentinel.txt
rm -f "$SENT"
J=tmp/rspec-r9b.json
OUT=tmp/rspec-r9b.out
rm -f "$J" "$OUT" tmp/rspec-r9b-*.txt
rc=0
bin/ci-local --only rspec --rspec-args "--options .rspec --require ./docs/specs/fork-updates-r9b-probes/r9b_sentinel.rb --format progress --format json --out $J $TARGET" > "$OUT" 2>&1 || rc=$?
tail -5 "$OUT"
echo "ci-local rspec rc=$rc"
test -s "$J" || { echo "FAIL: no rspec json (suite did not run)"; tail -40 "$OUT"; exit 1; }
row='.examples[] | "\(.file_path) :: \(.full_description)"'
jq -r ".examples[] | select(.status==\"failed\") | \"\(.file_path) :: \(.full_description)\"" "$J" | LC_ALL=C sort > tmp/rspec-r9b-failures.txt
jq -r ".examples[] | select(.status==\"pending\") | \"\(.file_path) :: \(.full_description)\"" "$J" | LC_ALL=C sort > tmp/rspec-r9b-pending.txt
jq -r "$row" "$J" | LC_ALL=C sort > tmp/rspec-r9b-examples.txt
total=$(jq -r '.summary.example_count' "$J")
failed=$(jq -r '.summary.failure_count' "$J")
pending=$(jq -r '.summary.pending_count' "$J")
outside=$(jq -r '.summary.errors_outside_of_examples_count' "$J")
echo "examples=$total failures=$failed pending=$pending errors_outside=$outside"
ran=$( (cat "$SENT" 2>/dev/null || :) | grep -c . || :)
ran=${ran:-0}
echo "bodies run (sentinel)=$ran"
# Warning-like lines of the suite output from the keyword on (progress dots dropped), with
# volatile parts (paths, numbers, ids) normalized.
warn_lines() {
  grep -oaE '(WARNING: |warning: |[A-Za-z_]*[Dd][Ee][Pp][Rr][Ee][Cc][Aa][Tt]).*' "$1" \
    | sed -E 's#/[^ :]*/##g; s/0x[0-9a-f]+/X/g; s/[0-9]+/N/g' | LC_ALL=C sort -u || [ $? -eq 1 ]
}
if [ "$ran" -lt $((total - pending)) ] || [ "$total" -eq 0 ]; then
  echo "FAIL: only $ran example bodies ran of $total examples ($pending pending): dry run or hooks skipped"; exit 1
fi
if [ "$MODE" = "--write-base" ]; then
  [ "$rc" = 0 ] && [ "$failed" = 0 ] && [ "$outside" = 0 ] || { echo "FAIL: suite not green, base not written"; exit 1; }
  sha=$(git rev-parse --short HEAD)
  { echo "# rspec examples at BASE $sha, $total examples, LC_ALL=C sorted"; cat tmp/rspec-r9b-examples.txt; } > "$HERE/examples_base.txt"
  { echo "# pending examples at BASE $sha ($pending), LC_ALL=C sorted"; cat tmp/rspec-r9b-pending.txt; } > "$HERE/pending_allowed.txt"
  { echo "# warning-like lines of the suite output at BASE $sha (normalized)"; warn_lines "$OUT"; } > "$HERE/warnings_base.txt"
  echo "WROTE examples_base.txt ($total), pending_allowed.txt ($pending), warnings_base.txt"
  exit 0
fi
if [ "$MODE" = "--only" ]; then
  if [ "$rc" = 0 ] && [ "$total" -gt 0 ] && [ "$failed" = 0 ] && [ "$outside" = 0 ]; then echo "PASS: $TARGET"; exit 0; fi
  echo "FAIL: $TARGET"; cat tmp/rspec-r9b-failures.txt; exit 1
fi
data_lines "$HERE/pending_allowed.txt" | LC_ALL=C sort > tmp/rspec-r9b-pending-allowed.txt
new_pending=$(LC_ALL=C comm -23 tmp/rspec-r9b-pending.txt tmp/rspec-r9b-pending-allowed.txt)
data_lines "$HERE/examples_base.txt" | LC_ALL=C sort > tmp/rspec-r9b-examples-base.txt
missing=$(LC_ALL=C comm -23 tmp/rspec-r9b-examples-base.txt tmp/rspec-r9b-examples.txt)
data_lines "$HERE/warnings_base.txt" | LC_ALL=C sort -u > tmp/rspec-r9b-warnings-base.txt
warn_lines "$OUT" > tmp/rspec-r9b-warnings.txt
new_warns=$(LC_ALL=C comm -23 tmp/rspec-r9b-warnings.txt tmp/rspec-r9b-warnings-base.txt)
ok=1
if [ "$rc" != 0 ]; then echo "FAIL: bin/ci-local rspec exited $rc"; ok=0; fi
if [ -n "$missing" ]; then echo "FAIL: BASE examples did not run:"; printf '%s\n' "$missing"; ok=0; fi
if [ "$failed" != 0 ]; then echo "FAIL: $failed failures:"; cat tmp/rspec-r9b-failures.txt; ok=0; fi
if [ "$outside" != 0 ]; then echo "FAIL: errors outside examples $outside"; ok=0; fi
if [ "$total" -lt "$MIN_EXAMPLES" ]; then echo "FAIL: example count $total < $MIN_EXAMPLES"; ok=0; fi
if [ -n "$new_pending" ]; then echo "FAIL: pending examples not allowed:"; printf '%s\n' "$new_pending"; ok=0; fi
if [ -n "$new_warns" ]; then echo "FAIL: warning lines BASE did not print:"; printf '%s\n' "$new_warns"; ok=0; fi
[ "$ok" = 1 ] && echo "PASS: full suite green, same examples as BASE" && exit 0
exit 1
