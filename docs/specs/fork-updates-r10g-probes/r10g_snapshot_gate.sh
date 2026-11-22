#!/usr/bin/env bash
# Snapshot gate for fork-updates-r10g (r10g_snapshot.rb, plain Ruby in the bin/ci-local image of .ruby-version):
#   1. BASE: the probe runs every snapshot case of r10g_config.json against BASE's presenter (git show) - every
#      result round-trips through JSON and every action element of the catalog is submitted by some case;
#   2. FIXTURES: the committed snapshot_dir (HEAD) holds exactly those files, byte for byte BASE's output;
#   3. TREE: the probe's output against HEAD's presenter is byte for byte BASE's output.
# Usage (from the repo root): bash docs/specs/fork-updates-r10g-probes/r10g_snapshot_gate.sh <BASE_SHA>
# Pass = "R10G SNAPSHOTS PASS <n> fixtures = BASE output = tree output", exit 0.
set -euo pipefail
BASE=${1:?usage: r10g_snapshot_gate.sh <BASE_SHA>}
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
CFG="$HERE/r10g_config.json"
IMG="chaskiq-ci-local:ruby-$(tr -d '[:space:]' < .ruby-version)-ubuntu-26.04"
docker image inspect "$IMG" >/dev/null 2>&1 || { echo "FAIL: image $IMG missing (built by bin/ci-local)"; exit 1; }
PRES=$(jq -r '.app_files[0]' "$CFG")
DIR=$(jq -r '.snapshot_dir' "$CFG")
N=$(jq '.snapshots | length' "$CFG")
[ "$N" -gt 0 ] && [ -n "$DIR" ] && [ "$DIR" != null ] || { echo "FAIL: config has no snapshots/snapshot_dir"; exit 1; }
W=tmp/r10g-snapshots
rm -rf "$W"
mkdir -p "$W/src" "$W/fixtures"
git show "$BASE:$PRES" > "$W/src/base_presenter.rb"
git show "HEAD:$PRES" > "$W/src/tree_presenter.rb"
cp "$HERE/r10g_snapshot.rb" "$CFG" "$W/src/"
# The committed fixtures (HEAD), not the work tree: AC-010 keeps the two equal.
if git cat-file -e "HEAD:$DIR" 2>/dev/null; then
  git archive HEAD "$DIR" | tar -x -C "$W/fixtures"
fi
mkdir -p "$W/fixtures/$DIR"
rc=0
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$ROOT/$W:/w" -w /w "$IMG" bash -c '
  set -e
  echo "== BASE"; ruby src/r10g_snapshot.rb src/r10g_config.json src/base_presenter.rb out/base
  echo "== TREE"; ruby src/r10g_snapshot.rb src/r10g_config.json src/tree_presenter.rb out/tree' || rc=$?
[ "$rc" = 0 ] || { echo "FAIL: snapshot probe exited $rc"; exit 1; }
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
echo "R10G SNAPSHOTS PASS $N fixtures = BASE output = tree output"
