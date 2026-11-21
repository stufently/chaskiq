#!/usr/bin/env bash
# Boot check for fork-updates-r2b: the application boots with the sorted Gemfile (Bundler.require
# order) and eager-loads all of its code. Runs `bin/rails runner` in the bin/ci-local image on a
# `git archive HEAD` copy, RAILS_ENV=test, without network (no database or Redis is needed to boot).
# Pass = the runner printed exactly "R2B BOOT OK <n> models" as its last line and exited 0.
# Usage (from the repo root): bash docs/specs/fork-updates-r2b-probes/r2b_boot.sh
set -euo pipefail
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
CACHE=${CHASKIQ_R2B_CACHE:-$HOME/.cache/chaskiq-r2b-ci}
IMG="chaskiq-ci-local:ruby-$(tr -d '[:space:]' < .ruby-version)-ubuntu-26.04"
docker image inspect "$IMG" >/dev/null 2>&1 || { echo "FAIL: image $IMG missing (built by bin/ci-local)"; exit 1; }
test -d "$CACHE/bundle-ubuntu-26.04" || { echo "FAIL: gem cache $CACHE/bundle-ubuntu-26.04 missing"; exit 1; }
W=tmp/r2b-boot
rm -rf "$W"
mkdir -p "$W/copy" vendor/bundle
git archive HEAD | tar -x -C "$W/copy"
rc=0
docker run --rm --network none --user "$(id -u):$(id -g)" -e HOME=/tmp -e BUNDLE_PATH=/bundle -e BUNDLE_FROZEN=true \
  -e BUNDLE_GEMFILE=/app/Gemfile -e RAILS_ENV=test -e BOOTSNAP_CACHE_DIR=/tmp/bootsnap \
  -v "$ROOT/$W/copy:/app" -v "$CACHE/bundle-ubuntu-26.04:/bundle:ro" -w /app "$IMG" \
  bin/rails runner 'Rails.application.eager_load!; puts "R2B BOOT OK #{ActiveRecord::Base.descendants.size} models"' \
  > "$W/out.txt" 2>&1 || rc=$?
tail -3 "$W/out.txt"
[ "$rc" = 0 ] || { echo "FAIL: bin/rails runner exited $rc"; tail -20 "$W/out.txt"; exit 1; }
tail -1 "$W/out.txt" | grep -qE '^R2B BOOT OK [1-9][0-9]* models$' || { echo "FAIL: no boot verdict"; exit 1; }
echo "R2B BOOT PASS"
