#!/usr/bin/env bash
# Backlog probe for fork-updates-r10g: RuboCop with .rubocop_todo.yml ignored, BASE against the tree.
# Pass = rubocop inspected exactly its target files on both sides without internal errors
# (stderr clean, no Lint/Syntax), every R10g cop has 0 offenses in the tree (cops_whole of r10g_config.json
# everywhere, cops_partial in the files listed for them), no other cop has more offenses in any file than
# at BASE (except todo_additions / allowed_growth of the config, each with its todo line), the resolved
# config has the show_cops values of the config, BASE's .rubocop.yml has every base_requires line of the
# config, and the total went down.
# Usage (from the repo root): bash docs/specs/fork-updates-r10g-probes/r10g_backlog_probe.sh <BASE_SHA>
# Runs in the bin/ci-local image of .ruby-version with the gems of ${CHASKIQ_R10G_CACHE:-$HOME/.cache/chaskiq-r10g-ci}.
# Only tracked files are linted on both sides (BASE from git archive, the tree from git ls-files),
# as in CI.
set -euo pipefail
BASE=${1:?usage: r10g_backlog_probe.sh <BASE_SHA>}
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
CACHE=${CHASKIQ_R10G_CACHE:-$HOME/.cache/chaskiq-r10g-ci}
IMG="chaskiq-ci-local:ruby-$(tr -d '[:space:]' < .ruby-version)-ubuntu-26.04"
docker image inspect "$IMG" >/dev/null 2>&1 || { echo "FAIL: image $IMG missing (built by bin/ci-local)"; exit 1; }
test -d "$CACHE/bundle-ubuntu-26.04" || { echo "FAIL: gem cache $CACHE/bundle-ubuntu-26.04 missing"; exit 1; }
W=tmp/r10g-backlog
rm -rf "$W"
trap 'rm -f "$ROOT/.rubocop_r10g_notodo.yml"' EXIT
mkdir -p "$W/base" vendor/bundle
git archive "$BASE" | tar -x -C "$W/base"
for side in base tree; do
  dir=$W/base
  [ "$side" = tree ] && dir=.
  head -1 "$dir/.rubocop.yml" | grep -qx 'inherit_from: .rubocop_todo.yml' \
    || { echo "FAIL: $side .rubocop.yml does not start with inherit_from: .rubocop_todo.yml"; exit 1; }
  tail -n +2 "$dir/.rubocop.yml" > "$dir/.rubocop_r10g_notodo.yml"
done
git ls-files -z -- '*.rb' '*.rake' '*.ru' '*.gemspec' '*.jbuilder' Gemfile Rakefile | tr '\0' '\n' > "$W/tree-files.txt"
(cd "$W/base" && find . -type f \( -name '*.rb' -o -name '*.rake' -o -name '*.ru' -o -name '*.gemspec' \
  -o -name '*.jbuilder' -o -name Gemfile -o -name Rakefile \) | sed 's#^\./##' | LC_ALL=C sort) > "$W/base-files.txt"
rc=0
# Create the bind-mount target as our user: if Docker creates it, it is root-owned in the clone.
mkdir -p "$ROOT/vendor/bundle"
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e BUNDLE_PATH=/app/vendor/bundle -e BUNDLE_FROZEN=true \
  -e BUNDLE_GEMFILE=/app/Gemfile -v "$ROOT:/app" -v "$CACHE/bundle-ubuntu-26.04:/app/vendor/bundle" -w /app "$IMG" \
  bash -c 'set -e
    bundle install --quiet
    mapfile -t tf < tmp/r10g-backlog/tree-files.txt
    bundle exec rubocop -c .rubocop_r10g_notodo.yml --cache false --force-exclusion --format json \
      --out tmp/r10g-backlog/tree.json "${tf[@]}" >/dev/null 2>tmp/r10g-backlog/tree.err || [ $? = 1 ]
    bundle exec rubocop -c .rubocop_r10g_notodo.yml --force-exclusion --list-target-files "${tf[@]}" \
      > tmp/r10g-backlog/tree-targets.txt
    cd tmp/r10g-backlog/base
    mapfile -t bf < ../base-files.txt
    bundle exec rubocop -c .rubocop_r10g_notodo.yml --cache false --force-exclusion --format json \
      --out ../base.json "${bf[@]}" >/dev/null 2>../base.err || [ $? = 1 ]
    bundle exec rubocop -c .rubocop_r10g_notodo.yml --force-exclusion --list-target-files "${bf[@]}" \
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
if jq -e '.show_cops' "$HERE/r10g_config.json" >/dev/null; then
  cops=$(jq -r '.show_cops | keys | join(",")' "$HERE/r10g_config.json")
  docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e BUNDLE_PATH=/app/vendor/bundle -e BUNDLE_FROZEN=true \
    -e BUNDLE_GEMFILE=/app/Gemfile -v "$ROOT:/app" -v "$CACHE/bundle-ubuntu-26.04:/app/vendor/bundle" -w /app "$IMG" \
    bundle exec rubocop --show-cops "$cops" > "$W/show-cops.txt" 2>"$W/show-cops.err" \
    || { echo "FAIL: rubocop --show-cops failed"; tail -5 "$W/show-cops.err"; exit 1; }
fi
python3 -I - "$HERE/r10g_config.json" "$W/base.json" "$W/tree.json" "$BASE" "$W/show-cops.txt" <<'EOF'
import json, os, re, subprocess, sys
cfg = json.load(open(sys.argv[1], encoding="utf-8"))
whole, partial = cfg["cops_whole"], cfg.get("cops_partial", {})
cops = whole + list(partial)
additions = cfg.get("todo_additions", {})   # {cop: [file]}: new todo lines the milestone may add
allowed = cfg.get("allowed_growth", {})     # {cop: {file: [base, tree]}}
def per_file(path):
    out = {}
    for f in json.load(open(path))["files"]:
        for o in f["offenses"]:
            out.setdefault(o["cop_name"], {}).setdefault(f["path"], 0)
            out[o["cop_name"]][f["path"]] += 1
    return out
base, cur = per_file(sys.argv[2]), per_file(sys.argv[3])
changed = set(subprocess.run(["git", "diff", "--name-only", sys.argv[4]], capture_output=True, text=True,
                             check=True).stdout.split())
todo, cop = {}, None
for line in open(".rubocop_todo.yml", encoding="utf-8"):
    m = re.match(r"^([A-Z][A-Za-z]+/[A-Za-z0-9]+):\s*$", line)
    if m:
        cop = m.group(1); todo[cop] = set(); continue
    m = re.match(r"^    - '([^']*)'", line)
    if m and cop:
        todo[cop].add(m.group(1))
fails = []
for c in whole:
    n = sum(cur.get(c, {}).values())
    if n:
        fails.append(f"{c}: {n} offenses left in the tree (BASE {sum(base.get(c, {}).values())})")
for c, files in partial.items():
    n = sum(cur.get(c, {}).get(f, 0) for f in files)
    if n:
        fails.append(f"{c}: {n} offenses left in the files of this milestone (BASE "
                     f"{sum(base.get(c, {}).get(f, 0) for f in files)})")
seen = set()
for c in sorted(cur):
    for f, n in sorted(cur[c].items()):
        if c in whole or f in partial.get(c, []):
            continue
        b = base.get(c, {}).get(f, 0)
        if n <= b:
            continue
        if f in additions.get(c, []) and f in todo.get(c, set()):
            print(f"note: {c} {f}: {b} -> {n} (todo addition listed in the config)")
            continue
        if allowed.get(c, {}).get(f) == [b, n] and f in changed and f in todo.get(c, set()):
            seen.add((c, f))
            print(f"note: {c} {f}: {b} -> {n} (listed in allowed_growth)")
            continue
        fails.append(f"{c} {f}: {n} offenses, BASE {b} (the change created new ones)")
for c, fs in allowed.items():
    for f, (b, n) in fs.items():
        if (c, f) not in seen:
            fails.append(f"allowed_growth {c} {f} {b} -> {n} not observed: BASE {base.get(c, {}).get(f, 0)}, "
                         f"tree {cur.get(c, {}).get(f, 0)}")
for c, files in additions.items():
    for f in files:
        if f not in todo.get(c, set()):
            fails.append(f"todo_additions {c} {f}: not in the todo")
# base_requires: lines BASE's .rubocop.yml must contain (a setting this milestone depends on, e.g. K1).
base_yml = subprocess.run(["git", "show", f"{sys.argv[4]}:.rubocop.yml"], capture_output=True, text=True,
                          check=True).stdout.split("\n")
for req in cfg.get("base_requires", []):
    if req not in base_yml:
        fails.append(f"BASE .rubocop.yml has no line {req!r}: the milestone needs it merged first (spec section 9)")
want_show = cfg.get("show_cops", {})
if want_show:
    text = open(sys.argv[5], encoding="utf-8").read()
    for c, kv in want_show.items():
        m = re.search(rf"(?ms)^{re.escape(c)}:\n(.*?)(?=^\S|\Z)", text)
        if not m:
            fails.append(f"--show-cops: no section {c}"); continue
        for k, v in kv.items():
            if not re.search(rf"(?m)^  {re.escape(k)}: {re.escape(v)}$", m.group(1)):
                fails.append(f"--show-cops: {c} has no '{k}: {v}' (resolved config)")
tb = sum(sum(v.values()) for v in base.values())
tt = sum(sum(v.values()) for v in cur.values())
nb = sum(sum(base.get(c, {}).values()) for c in whole) + \
    sum(base.get(c, {}).get(f, 0) for c, fs in partial.items() for f in fs)
print(f"backlog without todo: BASE {tb}, tree {tt}; R10g offenses at BASE {nb}")
if tt >= tb:
    fails.append(f"total did not go down: BASE {tb}, tree {tt}")
for f in fails:
    print("FAIL:", f)
sys.exit(1 if fails else print("R10G BACKLOG PASS"))
EOF
