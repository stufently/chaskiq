#!/usr/bin/env bash
# Snapshot gate for fork-updates-r10i (r10i_snapshot.rb: `bundle exec ruby` with ActiveSupport in the bin/ci-local
# image of .ruby-version, gems of ${CHASKIQ_R10I_CACHE:-$HOME/.cache/chaskiq-r10i-ci}; no Rails app, no network):
#   1. BASE: the probe runs every snapshot case of r10i_config.json against BASE's presenter (git show) - every
#      result round-trips through JSON, no unstubbed call to the fake API, every branch of the file is taken;
#   2. FIXTURES: the committed snapshot_dir (HEAD) holds exactly those files, byte for byte BASE's output;
#   3. TREE: the probe's output against HEAD's presenter is byte for byte BASE's output.
# Usage (from the repo root): bash docs/specs/fork-updates-r10i-probes/r10i_snapshot_gate.sh <BASE_SHA>
# Pass = "R10I SNAPSHOTS PASS <n> fixtures = BASE output = tree output", exit 0.
set -euo pipefail
BASE=${1:?usage: r10i_snapshot_gate.sh <BASE_SHA>}
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
CACHE=${CHASKIQ_R10I_CACHE:-$HOME/.cache/chaskiq-r10i-ci}
CFG="$HERE/r10i_config.json"
IMG="chaskiq-ci-local:ruby-$(tr -d '[:space:]' < .ruby-version)-ubuntu-26.04"
docker image inspect "$IMG" >/dev/null 2>&1 || { echo "FAIL: image $IMG missing (built by bin/ci-local)"; exit 1; }
test -d "$CACHE/bundle-ubuntu-26.04" || { echo "FAIL: gem cache $CACHE/bundle-ubuntu-26.04 missing"; exit 1; }
PRES=$(jq -r '.app_files[0]' "$CFG")
DIR=$(jq -r '.snapshot_dir' "$CFG")
N=$(jq '.snapshots | length' "$CFG")
[ "$N" -gt 0 ] && [ -n "$DIR" ] && [ "$DIR" != null ] || { echo "FAIL: config has no snapshots/snapshot_dir"; exit 1; }
W=tmp/r10i-snapshots
rm -rf "$W"
mkdir -p "$W/src" "$W/fixtures" vendor/bundle
git show "$BASE:$PRES" > "$W/src/base_presenter.rb"
git show "HEAD:$PRES" > "$W/src/tree_presenter.rb"
cp "$HERE/r10i_snapshot.rb" "$CFG" "$W/src/"
# The committed fixtures (HEAD), not the work tree: AC-010 keeps the two equal.
if git cat-file -e "HEAD:$DIR" 2>/dev/null; then
  git archive HEAD "$DIR" | tar -x -C "$W/fixtures"
fi
mkdir -p "$W/fixtures/$DIR"
rc=0
# The work tree's Gemfile/Gemfile.lock (AC-002 keeps them BASE's) give the gems; the probe needs only ActiveSupport.
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e BUNDLE_PATH=/bundle -e BUNDLE_FROZEN=true \
  -e BUNDLE_GEMFILE=/app/Gemfile -e BUNDLE_BUILD__SCOUT_APM="--with-cflags=-std=gnu17" \
  -v "$ROOT:/app:ro" -v "$CACHE/bundle-ubuntu-26.04:/bundle" -v "$ROOT/$W:/w" -w /w "$IMG" bash -c '
  set -e
  bundle install --quiet
  echo "== BASE"; bundle exec ruby src/r10i_snapshot.rb src/r10i_config.json src/base_presenter.rb out/base --coverage
  echo "== TREE"; bundle exec ruby src/r10i_snapshot.rb src/r10i_config.json src/tree_presenter.rb out/tree' \
  > "$W/probe.txt" 2>&1 || rc=$?
grep -E '^(==|R10I |FAIL)' "$W/probe.txt" || :
[ "$rc" = 0 ] || { echo "FAIL: snapshot probe exited $rc"; tail -20 "$W/probe.txt"; exit 1; }
ok=1
if ! diff -r "$W/out/base" "$W/fixtures/$DIR" > "$W/fixtures.diff"; then
  echo "FAIL: $DIR is not BASE's output (diff -r BASE-output fixtures):"; head -40 "$W/fixtures.diff"; ok=0
fi
if ! diff -r "$W/out/base" "$W/out/tree" > "$W/tree.diff"; then
  echo "FAIL: the tree's configure_hook output differs from BASE's (diff -r BASE tree):"; head -40 "$W/tree.diff"; ok=0
fi
nf=$(find "$W/out/base" -type f -name '*.json' | wc -l)
[ "$nf" = "$N" ] || { echo "FAIL: probe wrote $nf files for $N snapshots"; ok=0; }
[ "$ok" = 1 ] || exit 1
echo "R10I SNAPSHOTS PASS $N fixtures = BASE output = tree output"
