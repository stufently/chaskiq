#!/usr/bin/env bash
# Backlog probe for fork-updates-r8a: RuboCop with .rubocop_todo.yml ignored, BASE against the tree.
# Pass = rubocop inspected exactly its target files on both sides without internal errors (stderr
# clean, no Lint/Syntax); in the tree every R8 cop (r8_cops of r8a_config.json) reports exactly the
# outliers of the config (cop, file, count) and the todo block of each R8 cop lists exactly the files
# with such offenses; no other cop has more offenses in any file than at BASE; the resolved config
# (--show-cops without the todo) has the Max values, the Exclude lists and the AllowedPatterns of the
# config; the LineLength pattern probe (generated lines below) is reported exactly on the lines that
# must stay offenses (the "keep" lines avoid RuboCop's own AllowURI exemptions: a URL running to the end
# of the line up to the next space, or a `{...}` line ending in `}`); the total went down.
# Usage (from the repo root): bash docs/specs/fork-updates-r8a-probes/r8a_backlog_probe.sh <BASE_SHA>
# Runs in the bin/ci-local image of .ruby-version with the gems of ${CHASKIQ_R8A_CACHE:-$HOME/.cache/chaskiq-r8a-ci}.
# Only tracked files are linted on both sides (BASE from git archive, the tree from git ls-files), as in CI.
set -euo pipefail
BASE=${1:?usage: r8a_backlog_probe.sh <BASE_SHA>}
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
CACHE=${CHASKIQ_R8A_CACHE:-$HOME/.cache/chaskiq-r8a-ci}
IMG="chaskiq-ci-local:ruby-$(tr -d '[:space:]' < .ruby-version)-ubuntu-26.04"
docker image inspect "$IMG" >/dev/null 2>&1 || { echo "FAIL: image $IMG missing (built by bin/ci-local)"; exit 1; }
test -d "$CACHE/bundle-ubuntu-26.04" || { echo "FAIL: gem cache $CACHE/bundle-ubuntu-26.04 missing"; exit 1; }
W=tmp/r8a-backlog
rm -rf "$W"
trap 'rm -f "$ROOT/.rubocop_r8a_notodo.yml"' EXIT
mkdir -p "$W/base" vendor/bundle
git archive "$BASE" | tar -x -C "$W/base"
for side in base tree; do
  dir=$W/base
  [ "$side" = tree ] && dir=.
  head -1 "$dir/.rubocop.yml" | grep -qx 'inherit_from: .rubocop_todo.yml' \
    || { echo "FAIL: $side .rubocop.yml does not start with inherit_from: .rubocop_todo.yml"; exit 1; }
  tail -n +2 "$dir/.rubocop.yml" > "$dir/.rubocop_r8a_notodo.yml"
done
git ls-files -z -- '*.rb' '*.rake' '*.ru' '*.gemspec' '*.jbuilder' Gemfile Rakefile | tr '\0' '\n' > "$W/tree-files.txt"
(cd "$W/base" && find . -type f \( -name '*.rb' -o -name '*.rake' -o -name '*.ru' -o -name '*.gemspec' \
  -o -name '*.jbuilder' -o -name Gemfile -o -name Rakefile \) | sed 's#^\./##' | LC_ALL=C sort) > "$W/base-files.txt"
# Pattern probe: each generated line is longer than 140; "keep" lines must stay offenses.
python3 -I - "$W/pattern_probe.rb" "$W/pattern_expect.txt" <<'PY'
import sys
b64 = "QWxhZGRpbjpvcGVuIHNlc2FtZQ9xY2hhc2tpcStyOGEvcHJvYmUrYmFzZTY0PT0K" * 3
lines = [
    ("allow", '    { "url" => "https://cdn.example.com/' + "a1b2" * 40 + '.png" },'),
    ("allow", '    { "audio" => { "link" => "https://chat.example.com/uploads/' + "v" * 120 + '.ogg" } },'),
    ("allow", '    "' + b64 + '==",'),
    ("allow", '    { "sig" => "' + b64 + '=" },'),
    ("keep", '  h = [{ "link" => "https://chat.example.com/a.png", "caption" => "' + "c" * 120 + '" }, 1]'),
    ("keep", '  x = "' + "y" * 150 + '" + "https://example.com/z"'),
    ("keep", '  value = "' + "abcdefghij" * 16 + '"'),
    ("keep", '  h = { "v" => "' + b64 + '", "next" => "' + "n" * 20 + '" }'),
    ("keep", "  # " + "This comment is plain prose that runs well past the limit. " * 3),
    ("keep", '  json = \'{"a": {"href": "https://example.com/x"}, "b": "' + "q" * 120 + '"}\''),
]
# "allow" lines sit in an array literal (valid Ruby); without the AllowedPatterns each is an offense.
with open(sys.argv[1], "w") as f, open(sys.argv[2], "w") as e:
    f.write("# frozen_string_literal: true\n\nbegin\n  x = [\n")
    n, closed = 5, False
    for kind, text in lines:
        if kind == "keep" and not closed:
            f.write("    1\n  ]\n")
            n, closed = n + 2, True
        assert len(text) > 140, (n, len(text))
        f.write(text + "\n")
        e.write(f"{n} {kind}\n")
        n += 1
    f.write("end\n")
PY
jq -r '.r8_cops | join(",")' "$HERE/r8a_config.json" > "$W/cops.txt"
rc=0
# Create the bind-mount target as our user: if Docker creates it, it is root-owned in the clone.
mkdir -p "$ROOT/vendor/bundle"
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e BUNDLE_PATH=/app/vendor/bundle -e BUNDLE_FROZEN=true \
  -e BUNDLE_GEMFILE=/app/Gemfile -v "$ROOT:/app" -v "$CACHE/bundle-ubuntu-26.04:/app/vendor/bundle" -w /app "$IMG" \
  bash -c 'set -e
    bundle install --quiet
    mapfile -t tf < tmp/r8a-backlog/tree-files.txt
    bundle exec rubocop -c .rubocop_r8a_notodo.yml --cache false --force-exclusion --format json \
      --out tmp/r8a-backlog/tree.json "${tf[@]}" >/dev/null 2>tmp/r8a-backlog/tree.err || [ $? = 1 ]
    bundle exec rubocop -c .rubocop_r8a_notodo.yml --force-exclusion --list-target-files "${tf[@]}" \
      > tmp/r8a-backlog/tree-targets.txt
    bundle exec rubocop -c .rubocop_r8a_notodo.yml --show-cops "$(cat tmp/r8a-backlog/cops.txt)" \
      > tmp/r8a-backlog/show-cops.txt 2>tmp/r8a-backlog/show-cops.err
    bundle exec rubocop -c .rubocop_r8a_notodo.yml --cache false --only Layout/LineLength --format json \
      --out tmp/r8a-backlog/pattern.json tmp/r8a-backlog/pattern_probe.rb >/dev/null 2>tmp/r8a-backlog/pattern.err || [ $? = 1 ]
    cd tmp/r8a-backlog/base
    mapfile -t bf < ../base-files.txt
    bundle exec rubocop -c .rubocop_r8a_notodo.yml --cache false --force-exclusion --format json \
      --out ../base.json "${bf[@]}" >/dev/null 2>../base.err || [ $? = 1 ]
    bundle exec rubocop -c .rubocop_r8a_notodo.yml --force-exclusion --list-target-files "${bf[@]}" \
      > ../base-targets.txt' || rc=$?
[ "$rc" = 0 ] || { echo "FAIL: rubocop run failed (rc=$rc)"; cat "$W"/*.err 2>/dev/null | tail -20; exit 1; }
for side in base tree; do
  test -s "$W/$side.json" || { echo "FAIL: no rubocop json for $side"; exit 1; }
  # rc 1 means offenses, but an internal cop error also exits 1: it is only visible on stderr.
  if grep -aiE 'error occurred|errors occurred|An error|Error:|Traceback|undefined method|warning' "$W/$side.err"; then
    echo "FAIL: rubocop reported errors for $side (above)"; exit 1
  fi
  want=$(grep -c . "$W/$side-targets.txt" || [ $? -eq 1 ])
  got=$(jq -r '.summary.inspected_file_count' "$W/$side.json")
  [ "$got" = "$want" ] && [ "$want" -gt 0 ] \
    || { echo "FAIL: $side: rubocop inspected $got files, target list has $want"; exit 1; }
  syn=$(jq '[.files[].offenses[] | select(.cop_name == "Lint/Syntax")] | length' "$W/$side.json")
  [ "$syn" = 0 ] || { echo "FAIL: $side: $syn Lint/Syntax offenses (file does not parse)"; exit 1; }
done
test -s "$W/show-cops.txt" || { echo "FAIL: rubocop --show-cops gave nothing"; tail -5 "$W/show-cops.err"; exit 1; }
test -s "$W/pattern.json" || { echo "FAIL: no rubocop json for the pattern probe"; tail -5 "$W/pattern.err"; exit 1; }
python3 -I - "$HERE/r8a_config.json" "$W" <<'EOF'
import json, re, sys
cfg = json.load(open(sys.argv[1], encoding="utf-8"))
W = sys.argv[2]
cops, outl = cfg["r8_cops"], cfg["outliers"]
def per_file(path):
    out = {}
    for f in json.load(open(path))["files"]:
        for o in f["offenses"]:
            out.setdefault(o["cop_name"], {}).setdefault(f["path"], 0)
            out[o["cop_name"]][f["path"]] += 1
    return out
base, cur = per_file(f"{W}/base.json"), per_file(f"{W}/tree.json")
todo, cop = {}, None
for line in open(".rubocop_todo.yml", encoding="utf-8"):
    m = re.match(r"^([A-Z][A-Za-z]+/[A-Za-z0-9]+):\s*$", line)
    if m:
        cop = m.group(1); todo[cop] = set(); continue
    m = re.match(r"^    - '([^']*)'", line)
    if m and cop:
        todo[cop].add(m.group(1))
fails = []
for c in cops:
    got, want = cur.get(c, {}), outl.get(c, {})
    for f in sorted(set(got) | set(want)):
        if got.get(f, 0) != want.get(f, 0):
            fails.append(f"{c} {f}: {got.get(f, 0)} offenses, outlier list has {want.get(f, 0)}")
    if todo.get(c, set()) != set(got):
        extra, missing = sorted(todo.get(c, set()) - set(got)), sorted(set(got) - todo.get(c, set()))
        fails.append(f"todo {c}: lists {len(todo.get(c, set()))} files, offending files {len(got)}"
                     f" (not offending: {extra[:5]}; offending, not listed: {missing[:5]})")
adds, seen = cfg.get("todo_additions", {}), set()
for c in sorted(cur):
    if c in cops:
        continue
    for f, n in sorted(cur[c].items()):
        b = base.get(c, {}).get(f, 0)
        if n > b and f in adds.get(c, {}).get("files", []) and f in todo.get(c, set()):
            seen.add((c, f))
            print(f"note: {c} {f}: {b} -> {n} (todo addition of the config: Max 140 lets the modifier form fit)")
        elif n > b:
            fails.append(f"{c} {f}: {n} offenses, BASE {b} (the change created new ones)")
for c, add in adds.items():
    for f in add["files"]:
        if (c, f) not in seen:
            fails.append(f"todo addition {c} {f}: no new offense observed or file not in the todo block")
    if todo.get(c, set()) != set(add["files"]):
        fails.append(f"todo {c}: lists {sorted(todo.get(c, set()))}, expected exactly {add['files']}")
text = open(f"{W}/show-cops.txt", encoding="utf-8").read()
def section(c):
    m = re.search(rf"(?ms)^{re.escape(c)}:\n(.*?)(?=^\S|\Z)", text)
    return m.group(1) if m else None
for c, kv in cfg["show_cops"].items():
    s = section(c)
    if s is None:
        fails.append(f"--show-cops: no section {c}"); continue
    for k, v in kv.items():
        if not re.search(rf"(?m)^  {re.escape(k)}: {re.escape(v)}$", s):
            fails.append(f"--show-cops: {c} has no '{k}: {v}' (resolved config)")
for c, lists in cfg["show_lists"].items():
    s = section(c) or ""
    for k, want in lists.items():
        m = re.search(rf"(?m)^  {re.escape(k)}:\n((?:  - [^\n]*\n?)*)", s)
        got = None if not m else [re.sub(r'^  - "?(.*?)"?$', r"\1", l) for l in m.group(1).splitlines()]
        if got != want:
            fails.append(f"--show-cops: {c} {k} is {got}, expected {want}")
exp = dict(l.split() for l in open(f"{W}/pattern_expect.txt"))
pj = json.load(open(f"{W}/pattern.json"))["files"]
if any(o["cop_name"] == "Lint/Syntax" for f in pj for o in f["offenses"]):
    fails.append("pattern probe: generated file does not parse (spec defect)")
hit = {str(o["location"]["start_line"]) for f in pj for o in f["offenses"] if o["cop_name"] == "Layout/LineLength"}
for ln, kind in sorted(exp.items(), key=lambda kv: int(kv[0])):
    if (kind == "keep") != (ln in hit):
        fails.append(f"pattern probe line {ln}: {'no offense' if kind == 'keep' else 'offense'}, expected "
                     f"{'an offense' if kind == 'keep' else 'none (URL/base64 allowed)'}")
tb = sum(sum(v.values()) for v in base.values())
tt = sum(sum(v.values()) for v in cur.values())
rb = sum(sum(base.get(c, {}).values()) for c in cops)
rt = sum(sum(cur.get(c, {}).values()) for c in cops)
print(f"backlog without todo: BASE {tb}, tree {tt}; R8 cops BASE {rb}, tree {rt} (outliers)")
for c in cops:
    print(f"  {c}: BASE {sum(base.get(c, {}).values())}, tree {sum(cur.get(c, {}).values())} in {len(cur.get(c, {}))} files")
print(f"pattern probe: {sum(1 for k in exp.values() if k == 'allow')} allowed, {len(hit)} offenses")
if tt >= tb:
    fails.append(f"total did not go down: BASE {tb}, tree {tt}")
for f in fails:
    print("FAIL:", f)
sys.exit(1 if fails else print("R8A BACKLOG PASS"))
EOF
