#!/usr/bin/env bash
# Fixture gate for fork-updates-r10e: every fixture is byte for byte the BASE literal it replaces, a
# corrupted fixture is rejected, every ref gives the BASE value, and every changed spec file is BASE with
# the literals replaced by their refs, as bytecode (r10e_fixture_probe.rb; "R10E FIXTURES PASS …").
# Usage (from the repo root): bash docs/specs/fork-updates-r10e-probes/r10e_fixture_gate.sh <BASE_SHA>
# Runs plain Ruby (no gems: json, pathname, prism of the stdlib) in the bin/ci-local image of .ruby-version.
set -euo pipefail
BASE=${1:?usage: r10e_fixture_gate.sh <BASE_SHA>}
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
CFG=docs/specs/fork-updates-r10e-probes/r10e_config.json
IMG="chaskiq-ci-local:ruby-$(tr -d '[:space:]' < .ruby-version)-ubuntu-26.04"
docker image inspect "$IMG" >/dev/null 2>&1 || { echo "FAIL: image $IMG missing (built by bin/ci-local)"; exit 1; }
W=tmp/r10e-fixtures
rm -rf "$W"
mkdir -p "$W/base"
jq -r '.app_files[]' "$HERE/r10e_config.json" > "$W/app_files"
[ -s "$W/app_files" ] || { echo "FAIL: config lists no app_files"; exit 1; }
while IFS= read -r f; do
  mkdir -p "$W/base/$(dirname "$f")"
  git show "$BASE:$f" > "$W/base/$f"
done < "$W/app_files"
rc=0
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$ROOT:/app:ro" -w /app "$IMG" \
  ruby docs/specs/fork-updates-r10e-probes/r10e_fixture_probe.rb "$CFG" "$W/base" . || rc=$?
[ "$rc" = 0 ] || { echo "FAIL: fixture probe exited $rc"; exit 1; }
