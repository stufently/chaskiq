#!/usr/bin/env bash
# Gem resolution check for fork-updates-r2b (Bundler/OrderedGems sorts the Gemfile).
# Pass = (1) Gemfile.lock of HEAD and of the work tree is byte for byte BASE's (sorting gem lines
# legitimately changes nothing in it: Bundler writes DEPENDENCIES sorted by name); (2) the Gemfile of
# HEAD has exactly BASE's lines, only reordered (same multiset of lines); (3) on a `git archive HEAD`
# copy, `bundle lock --local` in the bin/ci-local image without network rewrites Gemfile.lock to
# exactly BASE's bytes, and `bundle check` passes.
# Usage (from the repo root): bash docs/specs/fork-updates-r2b-probes/r2b_gemlock.sh <BASE_SHA>
# Gems: ${CHASKIQ_R2B_CACHE:-$HOME/.cache/chaskiq-r2b-ci}/bundle-ubuntu-26.04 (read by bundler, mounted
# as the bundle path).
set -euo pipefail
BASE=${1:?usage: r2b_gemlock.sh <BASE_SHA>}
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
CACHE=${CHASKIQ_R2B_CACHE:-$HOME/.cache/chaskiq-r2b-ci}
IMG="chaskiq-ci-local:ruby-$(tr -d '[:space:]' < .ruby-version)-ubuntu-26.04"
docker image inspect "$IMG" >/dev/null 2>&1 || { echo "FAIL: image $IMG missing (built by bin/ci-local)"; exit 1; }
test -d "$CACHE/bundle-ubuntu-26.04" || { echo "FAIL: gem cache $CACHE/bundle-ubuntu-26.04 missing"; exit 1; }
W=tmp/r2b-gemlock
rm -rf "$W"
mkdir -p "$W/copy" vendor/bundle
git show "$BASE:Gemfile.lock" > "$W/base.lock"
git show "$BASE:Gemfile" > "$W/base.gemfile"
git show "HEAD:Gemfile" > "$W/head.gemfile"
git show "HEAD:Gemfile.lock" > "$W/head.lock"
cmp -s "$W/base.lock" "$W/head.lock" || { echo "FAIL: Gemfile.lock of HEAD differs from BASE"; exit 1; }
cmp -s "$W/base.lock" Gemfile.lock || { echo "FAIL: Gemfile.lock of the work tree differs from BASE"; exit 1; }
if ! cmp -s <(LC_ALL=C sort "$W/base.gemfile") <(LC_ALL=C sort "$W/head.gemfile"); then
  echo "FAIL: the Gemfile of HEAD is not BASE's lines reordered:"
  diff <(LC_ALL=C sort "$W/base.gemfile") <(LC_ALL=C sort "$W/head.gemfile") | head -20
  exit 1
fi
cmp -s "$W/base.gemfile" "$W/head.gemfile" && { echo "FAIL: the Gemfile of HEAD is BASE's (not sorted)"; exit 1; }
git archive HEAD | tar -x -C "$W/copy"
rc=0
docker run --rm --network none --user "$(id -u):$(id -g)" -e HOME=/tmp -e BUNDLE_PATH=/bundle \
  -e BUNDLE_GEMFILE=/app/Gemfile -v "$ROOT/$W/copy:/app" -v "$CACHE/bundle-ubuntu-26.04:/bundle:ro" -w /app "$IMG" \
  bash -c 'bundle lock --local && bundle check' > "$W/out.txt" 2>&1 || rc=$?
tail -3 "$W/out.txt"
[ "$rc" = 0 ] || { echo "FAIL: bundle lock --local / bundle check exited $rc"; tail -20 "$W/out.txt"; exit 1; }
if ! cmp -s "$W/base.lock" "$W/copy/Gemfile.lock"; then
  echo "FAIL: bundle lock --local changed Gemfile.lock:"; diff "$W/base.lock" "$W/copy/Gemfile.lock" | head -20; exit 1
fi
echo "R2B GEMLOCK PASS"
