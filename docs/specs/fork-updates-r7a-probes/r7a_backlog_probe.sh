#!/usr/bin/env bash
# Backlog probe for fork-updates-r7a: RuboCop with .rubocop_todo.yml ignored, BASE against the tree.
# Pass = rubocop inspected exactly its target files on both sides without internal errors
# (stderr clean, no Lint/Syntax), the same target files on both sides, the three cops of R7A_COPS
# (r7a_probe.py) have 0 offenses in the tree (disabled), every other cop has exactly the BASE
# offenses in every file, and the total went down by exactly the BASE count of the three cops.
# Usage (from the repo root): bash docs/specs/fork-updates-r7a-probes/r7a_backlog_probe.sh <BASE_SHA>
# Runs in the bin/ci-local image of .ruby-version with the gems of ${CHASKIQ_R7A_CACHE:-$HOME/.cache/chaskiq-r7a-ci}.
# Only tracked files are linted on both sides (BASE from git archive, the tree from git ls-files),
# as in CI.
set -euo pipefail
BASE=${1:?usage: r7a_backlog_probe.sh <BASE_SHA>}
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
CACHE=${CHASKIQ_R7A_CACHE:-$HOME/.cache/chaskiq-r7a-ci}
IMG="chaskiq-ci-local:ruby-$(tr -d '[:space:]' < .ruby-version)-ubuntu-26.04"
docker image inspect "$IMG" >/dev/null 2>&1 || { echo "FAIL: image $IMG missing (built by bin/ci-local)"; exit 1; }
test -d "$CACHE/bundle-ubuntu-26.04" || { echo "FAIL: gem cache $CACHE/bundle-ubuntu-26.04 missing"; exit 1; }
W=tmp/r7a-backlog
rm -rf "$W"
trap 'rm -f "$ROOT/.rubocop_r7a_notodo.yml"' EXIT
mkdir -p "$W/base" vendor/bundle
git archive "$BASE" | tar -x -C "$W/base"
for side in base tree; do
  dir=$W/base
  [ "$side" = tree ] && dir=.
  head -1 "$dir/.rubocop.yml" | grep -qx 'inherit_from: .rubocop_todo.yml' \
    || { echo "FAIL: $side .rubocop.yml does not start with inherit_from: .rubocop_todo.yml"; exit 1; }
  tail -n +2 "$dir/.rubocop.yml" > "$dir/.rubocop_r7a_notodo.yml"
done
git ls-files -z -- '*.rb' '*.rake' '*.ru' '*.gemspec' '*.jbuilder' Gemfile Rakefile | tr '\0' '\n' > "$W/tree-files.txt"
(cd "$W/base" && find . -type f \( -name '*.rb' -o -name '*.rake' -o -name '*.ru' -o -name '*.gemspec' \
  -o -name '*.jbuilder' -o -name Gemfile -o -name Rakefile \) | sed 's#^\./##' | LC_ALL=C sort) > "$W/base-files.txt"
rc=0
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e BUNDLE_PATH=/app/vendor/bundle -e BUNDLE_FROZEN=true \
  -e BUNDLE_GEMFILE=/app/Gemfile -v "$ROOT:/app" -v "$CACHE/bundle-ubuntu-26.04:/app/vendor/bundle" -w /app "$IMG" \
  bash -c 'set -e
    bundle install --quiet
    mapfile -t tf < tmp/r7a-backlog/tree-files.txt
    bundle exec rubocop -c .rubocop_r7a_notodo.yml --cache false --force-exclusion --format json \
      --out tmp/r7a-backlog/tree.json "${tf[@]}" >/dev/null 2>tmp/r7a-backlog/tree.err || [ $? = 1 ]
    bundle exec rubocop -c .rubocop_r7a_notodo.yml --force-exclusion --list-target-files "${tf[@]}" \
      > tmp/r7a-backlog/tree-targets.txt
    cd tmp/r7a-backlog/base
    mapfile -t bf < ../base-files.txt
    bundle exec rubocop -c .rubocop_r7a_notodo.yml --cache false --force-exclusion --format json \
      --out ../base.json "${bf[@]}" >/dev/null 2>../base.err || [ $? = 1 ]
    bundle exec rubocop -c .rubocop_r7a_notodo.yml --force-exclusion --list-target-files "${bf[@]}" \
      > ../base-targets.txt' || rc=$?
[ "$rc" = 0 ] || { echo "FAIL: rubocop run failed (rc=$rc)"; cat "$W/tree.err" "$W/base.err" 2>/dev/null | tail -20; exit 1; }
for side in base tree; do
  test -s "$W/$side.json" || { echo "FAIL: no rubocop json for $side"; exit 1; }
  # rc 1 means offenses, but an internal cop error also exits 1: it is only visible on stderr.
  if grep -aiE 'error occurred|errors occurred|An error|Error:|Traceback|undefined method' "$W/$side.err"; then
    echo "FAIL: rubocop reported errors for $side (above)"; exit 1
  fi
  want=$(grep -c . "$W/$side-targets.txt" || [ $? -eq 1 ])
  got=$(jq -r '.summary.inspected_file_count' "$W/$side.json")
  [ "$got" = "$want" ] && [ "$want" -gt 0 ] \
    || { echo "FAIL: $side: rubocop inspected $got files, target list has $want"; exit 1; }
  syn=$(jq '[.files[].offenses[] | select(.cop_name == "Lint/Syntax")] | length' "$W/$side.json")
  [ "$syn" = 0 ] || { echo "FAIL: $side: $syn Lint/Syntax offenses (file does not parse)"; exit 1; }
  jq '[.files[].offenses[].cop_name] | group_by(.) | map({key: .[0], value: length}) | from_entries' \
    "$W/$side.json" > "$W/$side-counts.json"
done
python3 -I - "$HERE/r7a_probe.py" "$W/base.json" "$W/tree.json" "$W/base-targets.txt" "$W/tree-targets.txt" <<'EOF'
import ast, json, sys
tree = ast.parse(open(sys.argv[1], encoding="utf-8").read())
cops = next(ast.literal_eval(n.value) for n in tree.body
            if isinstance(n, ast.Assign) and getattr(n.targets[0], "id", "") == "R7A_COPS")
def per_file(path):
    out = {}
    for f in json.load(open(path))["files"]:
        for o in f["offenses"]:
            out.setdefault(o["cop_name"], {}).setdefault(f["path"], 0)
            out[o["cop_name"]][f["path"]] += 1
    return out
base, cur = per_file(sys.argv[2]), per_file(sys.argv[3])
fails = []
bt = sorted(open(sys.argv[4]).read().split()); tt = sorted(open(sys.argv[5]).read().split())
if bt != tt:
    fails.append(f"target files differ: only BASE {sorted(set(bt) - set(tt))[:5]}, only tree {sorted(set(tt) - set(bt))[:5]}")
for c in cops:
    n = sum(cur.get(c, {}).values())
    if n:
        fails.append(f"{c}: {n} offenses in the tree (cop must be disabled)")
for c in sorted((set(cur) | set(base)) - set(cops)):
    if cur.get(c, {}) != base.get(c, {}):
        diff = sorted(f for f in set(cur.get(c, {})) | set(base.get(c, {}))
                      if cur.get(c, {}).get(f, 0) != base.get(c, {}).get(f, 0))
        fails.append(f"{c}: offenses changed in {diff[:5]} (R7a changes no other cop)")
tb = sum(sum(v.values()) for v in base.values())
tt_ = sum(sum(v.values()) for v in cur.values())
gone = sum(sum(base.get(c, {}).values()) for c in cops)
print(f"backlog without todo: BASE {tb}, tree {tt_}; R7A cops at BASE {gone} (" +
      ", ".join(f"{c} {sum(base.get(c, {}).values())}" for c in cops) + ")")
if tt_ != tb - gone:
    fails.append(f"total {tt_} != BASE {tb} - {gone}")
for f in fails:
    print("FAIL:", f)
sys.exit(1 if fails else print("R7A BACKLOG PASS"))
EOF
