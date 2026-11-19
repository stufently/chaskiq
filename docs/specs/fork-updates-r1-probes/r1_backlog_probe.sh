#!/usr/bin/env bash
# Backlog probe for fork-updates-r1: RuboCop with .rubocop_todo.yml ignored, BASE against the tree.
# Pass = rubocop inspected exactly its target files on both sides without internal errors
# (stderr clean, no Lint/Syntax), every R1 cop (list in r1_equiv_probe.py) has 0 offenses in the tree, no other cop has more
# offenses than at BASE, and the total went down.
# Usage (from the repo root): bash docs/specs/fork-updates-r1-probes/r1_backlog_probe.sh <BASE_SHA>
# Runs in the bin/ci-local image of .ruby-version with the gems of ${CHASKIQ_R1_CACHE:-$HOME/.cache/chaskiq-r1-ci}.
# Only tracked files are linted on both sides (BASE from git archive, the tree from git ls-files),
# as in CI.
set -euo pipefail
BASE=${1:?usage: r1_backlog_probe.sh <BASE_SHA>}
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
CACHE=${CHASKIQ_R1_CACHE:-$HOME/.cache/chaskiq-r1-ci}
IMG="chaskiq-ci-local:ruby-$(tr -d '[:space:]' < .ruby-version)-ubuntu-26.04"
docker image inspect "$IMG" >/dev/null 2>&1 || { echo "FAIL: image $IMG missing (built by bin/ci-local)"; exit 1; }
test -d "$CACHE/bundle-ubuntu-26.04" || { echo "FAIL: gem cache $CACHE/bundle-ubuntu-26.04 missing"; exit 1; }
W=tmp/r1-backlog
rm -rf "$W"
trap 'rm -f "$ROOT/.rubocop_r1_notodo.yml"' EXIT
mkdir -p "$W/base" vendor/bundle
git archive "$BASE" | tar -x -C "$W/base"
for side in base tree; do
  dir=$W/base
  [ "$side" = tree ] && dir=.
  head -1 "$dir/.rubocop.yml" | grep -qx 'inherit_from: .rubocop_todo.yml' \
    || { echo "FAIL: $side .rubocop.yml does not start with inherit_from: .rubocop_todo.yml"; exit 1; }
  tail -n +2 "$dir/.rubocop.yml" > "$dir/.rubocop_r1_notodo.yml"
done
git ls-files -z -- '*.rb' '*.rake' '*.ru' '*.gemspec' '*.jbuilder' Gemfile Rakefile | tr '\0' '\n' > "$W/tree-files.txt"
(cd "$W/base" && find . -type f \( -name '*.rb' -o -name '*.rake' -o -name '*.ru' -o -name '*.gemspec' \
  -o -name '*.jbuilder' -o -name Gemfile -o -name Rakefile \) | sed 's#^\./##' | LC_ALL=C sort) > "$W/base-files.txt"
rc=0
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e BUNDLE_PATH=/app/vendor/bundle -e BUNDLE_FROZEN=true \
  -e BUNDLE_GEMFILE=/app/Gemfile -v "$ROOT:/app" -v "$CACHE/bundle-ubuntu-26.04:/app/vendor/bundle" -w /app "$IMG" \
  bash -c 'set -e
    bundle install --quiet
    mapfile -t tf < tmp/r1-backlog/tree-files.txt
    bundle exec rubocop -c .rubocop_r1_notodo.yml --cache false --force-exclusion --format json \
      --out tmp/r1-backlog/tree.json "${tf[@]}" >/dev/null 2>tmp/r1-backlog/tree.err || [ $? = 1 ]
    bundle exec rubocop -c .rubocop_r1_notodo.yml --force-exclusion --list-target-files "${tf[@]}" \
      > tmp/r1-backlog/tree-targets.txt
    cd tmp/r1-backlog/base
    mapfile -t bf < ../base-files.txt
    bundle exec rubocop -c .rubocop_r1_notodo.yml --cache false --force-exclusion --format json \
      --out ../base.json "${bf[@]}" >/dev/null 2>../base.err || [ $? = 1 ]
    bundle exec rubocop -c .rubocop_r1_notodo.yml --force-exclusion --list-target-files "${bf[@]}" \
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
python3 -I - "$HERE/r1_equiv_probe.py" "$W/base-counts.json" "$W/tree-counts.json" <<'EOF'
import ast, json, sys
src = open(sys.argv[1], encoding="utf-8").read()
tree = ast.parse(src)
cops = next(ast.literal_eval(n.value) for n in tree.body
            if isinstance(n, ast.Assign) and getattr(n.targets[0], "id", "") == "R1_COPS")
base = json.load(open(sys.argv[2]))
cur = json.load(open(sys.argv[3]))
fails = []
for c in cops:
    if cur.get(c, 0):
        fails.append(f"{c}: {cur[c]} offenses left in the tree (BASE {base.get(c, 0)})")
for c in sorted(set(cur) - set(cops)):
    if cur[c] > base.get(c, 0):
        fails.append(f"{c}: {cur[c]} offenses, BASE {base.get(c, 0)} (autocorrect created new ones)")
tb, tt = sum(base.values()), sum(cur.values())
print(f"backlog without todo: BASE {tb}, tree {tt}; R1 cops at BASE {sum(base.get(c, 0) for c in cops)}")
if tt >= tb:
    fails.append(f"total did not go down: BASE {tb}, tree {tt}")
for f in fails:
    print("FAIL:", f)
sys.exit(1 if fails else print("R1 BACKLOG PASS"))
EOF
