#!/usr/bin/env bash
# Zeitwerk check for fork-updates-r7d: every class moved to its own file keeps its constant name and
# surface, and Zeitwerk can autoload it from its new file.
# On `git archive` copies of BASE and HEAD, in the bin/ci-local image without network (RAILS_ENV=test,
# no database or Redis is needed to boot):
#   1. HEAD: `bin/rails zeitwerk:check` passes ("All is good!");
#   2. BASE and HEAD: r7d_boot.rb (bin/rails runner) records where Zeitwerk would autoload each moved
#      constant from, then runs Rails.application.eager_load! and Zeitwerk::Loader.eager_load_all and
#      records the surface of the moved constants and their former host classes;
# Pass = zeitwerk:check passed; on HEAD every moved constant autoloads from the file named in "moved"
# of r7d_config.json; the surface of every constant is identical on BASE and HEAD; no moved constant
# is an Active Record model or an Active Job. Prints "R7D BOOT PASS".
# Usage (from the repo root): bash docs/specs/fork-updates-r7d-probes/r7d_boot.sh <BASE_SHA>
set -euo pipefail
BASE=${1:?usage: r7d_boot.sh <BASE_SHA>}
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
CACHE=${CHASKIQ_R7D_CACHE:-$HOME/.cache/chaskiq-r7d-ci}
IMG="chaskiq-ci-local:ruby-$(tr -d '[:space:]' < .ruby-version)-ubuntu-26.04"
docker image inspect "$IMG" >/dev/null 2>&1 || { echo "FAIL: image $IMG missing (built by bin/ci-local)"; exit 1; }
test -d "$CACHE/bundle-ubuntu-26.04" || { echo "FAIL: gem cache $CACHE/bundle-ubuntu-26.04 missing"; exit 1; }
W=tmp/r7d-boot
rm -rf "$W"
mkdir -p "$W/base" "$W/head" vendor/bundle
git archive "$BASE" | tar -x -C "$W/base"
git archive HEAD | tar -x -C "$W/head"
for side in base head; do
  cp "$HERE/r7d_boot.rb" "$HERE/r7d_config.json" "$W/$side/tmp/" 2>/dev/null || { mkdir -p "$W/$side/tmp"; cp "$HERE/r7d_boot.rb" "$HERE/r7d_config.json" "$W/$side/tmp/"; }
done
run() {
  local side=$1; shift
  docker run --rm --network none --user "$(id -u):$(id -g)" -e HOME=/tmp -e BUNDLE_PATH=/bundle -e BUNDLE_FROZEN=true \
    -e BUNDLE_GEMFILE=/app/Gemfile -e RAILS_ENV=test -e BOOTSNAP_CACHE_DIR=/tmp/bootsnap \
    -v "$ROOT/$W/$side:/app" -v "$CACHE/bundle-ubuntu-26.04:/bundle:ro" -w /app "$IMG" "$@"
}
rc=0
run head bin/rails zeitwerk:check > "$W/zeitwerk.txt" 2>&1 || rc=$?
tail -3 "$W/zeitwerk.txt"
[ "$rc" = 0 ] && grep -q "All is good" "$W/zeitwerk.txt" || { echo "FAIL: bin/rails zeitwerk:check (rc=$rc)"; tail -20 "$W/zeitwerk.txt"; exit 1; }
for side in base head; do
  rc=0
  run "$side" bin/rails runner tmp/r7d_boot.rb tmp/r7d_config.json tmp/r7d_boot.json > "$W/$side.txt" 2>&1 || rc=$?
  tail -1 "$W/$side.txt"
  [ "$rc" = 0 ] && test -s "$W/$side/tmp/r7d_boot.json" || { echo "FAIL: $side runner exited $rc"; tail -20 "$W/$side.txt"; exit 1; }
done
python3 -I - "$HERE/r7d_config.json" "$W/base/tmp/r7d_boot.json" "$W/head/tmp/r7d_boot.json" <<'PY'
import json, sys
cfg = json.load(open(sys.argv[1], encoding="utf-8"))
base, head = (json.load(open(p, encoding="utf-8")) for p in sys.argv[2:4])
fails = []
for name, (path, host) in cfg["moved"].items():
    got = head["autoload"].get(name)
    print(f"{name}: autoloads from {got} (BASE: {base['autoload'].get(name)})")
    if got != path:
        fails.append(f"{name}: HEAD autoloads it from {got!r}, expected {path!r}")
for name in sorted(set(base["surface"]) | set(head["surface"])):
    b, h = base["surface"].get(name), head["surface"].get(name)
    if b != h:
        keys = sorted(k for k in set(b or {}) | set(h or {}) if (b or {}).get(k) != (h or {}).get(k))
        fails.append(f"{name}: surface differs from BASE in {keys}: BASE {[(b or {}).get(k) for k in keys]}, HEAD {[(h or {}).get(k) for k in keys]}")
    elif name in cfg["moved"] and (h["active_record"] or h["active_job"]):
        fails.append(f"{name}: is an Active Record model or Active Job (spec defect: class names are persisted)")
for f in fails:
    print("FAIL:", f)
sys.exit(1 if fails else print("R7D BOOT PASS"))
PY
