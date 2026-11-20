#!/usr/bin/env python3
"""Probe for mut-m9-m14b (kill the mutants mut-m9-m14 wrongly marked equivalent).

Usage (from the repo root):
  python3 -I docs/specs/mut-m9-m14b-probes/mutb_probe.py scope <BASE_SHA>
  python3 -I docs/specs/mut-m9-m14b-probes/mutb_probe.py check <BASE_SHA>
  python3 -I docs/specs/mut-m9-m14b-probes/mutb_probe.py jobs        (used by mutb_kill_gate.sh)

Inputs next to this file: kill_table.json (mutants to kill, patches in patches/), classified.json
(equivalent / invalid / defect, decided by the coordinator), and the first pass's
docs/specs/mut-m9-m14-results/manifest.json with docs/specs/mut-m9-m14-probes/targets.json.
The executor writes tmp/mutants-b/manifest.json (untracked, never committed):
  {"mutants": [{"id": "M024", "status": "killed|killed_new", "specs": ["spec/..._spec.rb", ...],
                "test_added": "spec/..._spec.rb" (killed_new only)}]}

scope: the only changes against BASE are added or modified regular files under spec/; every commit of
  BASE..HEAD (first parent, no merges) too; nothing outside spec/ differs from BASE in HEAD or the work
  tree; no untracked file except report.json, report-blocked.md; no ignored-but-present .rspec* or
  file under app/, lib/, config/, spec/, vendor/nightfury, vendor/php_serialize.
check: 1. the executor manifest has exactly the ids of kill_table.json, each killed or killed_new,
  specs = existing spec files, killed_new: test_added listed in specs and changed since BASE;
  2. the final classification = first-pass manifest + kill table (statuses from the executor) +
  classified.json (equivalent / invalid dropped / defect) has no "survived" and no equivalent whose
  reason is shorter than 20 characters or matches REASON_BAN (a reason about the tests is a survivor);
  3. per target of targets.json: >= min_mutants killed mutants, equivalent <= 20% of the target's
  mutants (invalid and defect ones not counted).
jobs: prints the jobs for mutb_kill.rb - every kill-table mutant listed in the executor manifest, with
  the patch of this directory and the manifest's specs / test_added (exit 1 if the manifest is
  unreadable; missing ids are skipped - mutb_kill_gate.sh without --only then fails on the count).
Prints one "FAIL:" line per problem and "MUTB SCOPE PASS" / "MUTB CHECK PASS".
"""
import json
import pathlib
import re
import subprocess
import sys

REASON_BAN = re.compile(r"test|spec|not loaded|exercis|assert|concurren|normal conditions", re.I)
args = sys.argv[1:]
if not args or args[0] not in ("scope", "check", "jobs") or (args[0] != "jobs" and len(args) != 2):
    sys.exit("usage: mutb_probe.py scope|check <BASE_SHA> | jobs")
MODE = args[0]
BASE = args[1] if len(args) > 1 else None
ROOT = pathlib.Path(subprocess.run(["git", "rev-parse", "--show-toplevel"], check=True,
                                   capture_output=True, text=True).stdout.strip())
HERE = pathlib.Path(__file__).resolve().parent
UNTRACKED_OK = {"report.json", "report-blocked.md"}
fails = []


def git(*a, check=True):
    r = subprocess.run(["git", "-C", str(ROOT), *a], capture_output=True, text=True)
    if check and r.returncode != 0:
        print(f"FAIL: git {' '.join(a)}: {r.stderr.strip()[:300]}")
        sys.exit(1)
    return r


def load(path, key=None):
    try:
        data = json.loads(pathlib.Path(path).read_text(encoding="utf-8"))
        return data[key] if key else data
    except (OSError, ValueError, KeyError, TypeError) as e:
        print(f"FAIL: {path}: {e}")
        sys.exit(1)


def mode_check(raw, where):
    for line in raw.splitlines():
        parts = line.split("\t", 1)
        meta = parts[0].split()
        if len(meta) < 5 or len(parts) < 2:
            continue
        old, new, status, path = meta[0].lstrip(":"), meta[1], meta[4], parts[1]
        if not path.startswith("spec/"):
            fails.append(f"{where}: {path}: outside spec/ (production files are never changed)")
        if status in ("D", "T") or (status != "A" and old != new) or new not in ("100644", "100755"):
            fails.append(f"{where}: {path}: status {status}, mode {old} -> {new} (only added/modified regular files)")


def executor_manifest(kill_ids):
    mpath = ROOT / "tmp" / "mutants-b" / "manifest.json"
    rows = load(mpath, "mutants")
    seen = {}
    for r in rows:
        mid = r.get("id")
        if mid in seen:
            fails.append(f"{mid}: duplicate id in the executor manifest")
        seen[mid] = r
    for mid in sorted(set(seen) - set(kill_ids)):
        fails.append(f"{mid}: not in kill_table.json (the executor manifest lists only kill-table mutants)")
    for mid in kill_ids:
        if mid not in seen:
            fails.append(f"{mid}: missing from tmp/mutants-b/manifest.json")
    return seen


if MODE == "scope":
    mode_check(git("diff", "--raw", "--no-renames", BASE).stdout, "tree")
    if git("diff", "--quiet", BASE, "HEAD", "--", ".", ":(exclude)spec", check=False).returncode != 0:
        fails.append("HEAD differs from BASE outside spec/")
    if git("diff", "--quiet", "HEAD", "--", ".", ":(exclude)spec", check=False).returncode != 0:
        fails.append("work tree differs from HEAD outside spec/ (a mutant left applied?)")
    if git("rev-list", "--merges", f"{BASE}..HEAD").stdout.split():
        fails.append("merge commits in BASE..HEAD")
    for sha in git("rev-list", "--reverse", "--first-parent", f"{BASE}..HEAD").stdout.split():
        mode_check(git("diff-tree", "--raw", "-r", "--no-renames", "--no-commit-id", sha).stdout, f"commit {sha[:12]}")
    untracked = [p for p in git("ls-files", "--others", "--exclude-standard").stdout.splitlines()
                 if p and p not in UNTRACKED_OK]
    if untracked:
        fails.append(f"untracked files: {untracked[:10]}")
    for line in git("status", "--porcelain", "--ignored=matching", "--untracked-files=all").stdout.splitlines():
        p = line[3:]
        if line.startswith("!! ") and (re.match(r"^(\.rspec|(app|lib|config|spec|vendor/nightfury|vendor/php_serialize)/)", p)
                                        or p.endswith(".rspec-local")):
            fails.append(f"{p}: ignored but present (affects the test run)")
    print(f"changed spec files: {len(git('diff', '--name-only', BASE).stdout.split())}")
else:
    kill = load(HERE / "kill_table.json")
    kill_ids = [k["id"] for k in kill]
    seen = executor_manifest(kill_ids)
    if MODE == "jobs":
        # lenient on purpose: ids missing from the executor manifest are skipped here (a quick --only
        # check while writing tests); the gate without --only requires every kill-table id, and
        # `check` fails on any missing one.
        jobs = [{"id": k["id"], "file": k["file"], "patch": k["patch"].removeprefix("patches/"),
                 "specs": seen[k["id"]].get("specs") or [],
                 "test_added": seen[k["id"]].get("test_added") if seen[k["id"]].get("status") == "killed_new" else None}
                for k in kill if k["id"] in seen]
        print(json.dumps(jobs, indent=1))
        sys.exit(0)
    changed_specs = set(git("diff", "--name-only", BASE, "--", "spec").stdout.split())
    for mid, r in seen.items():
        if mid not in kill_ids:
            continue
        st = r.get("status")
        if st not in ("killed", "killed_new"):
            fails.append(f"{mid}: status {st!r} - every kill-table mutant must be killed (doubt -> section 9)")
        specs = r.get("specs") or []
        if not specs or any(not re.match(r"^spec/.*_spec\.rb$", s) or not (ROOT / s).is_file() for s in specs):
            fails.append(f"{mid}: specs missing or not existing spec files: {specs}")
        if st == "killed_new":
            ta = r.get("test_added") or ""
            if ta not in changed_specs or ta not in specs:
                fails.append(f"{mid}: test_added {ta!r} is not a spec file changed since BASE listed in specs")
    # final classification ---------------------------------------------------------------------------
    first = {m["id"]: dict(m) for m in load(ROOT / "docs/specs/mut-m9-m14-results/manifest.json", "mutants")}
    cls = load(HERE / "classified.json")
    final = dict(first)
    for k in kill:
        row = final.setdefault(k["id"], {"id": k["id"], "milestone": k["milestone"], "file": k["file"]})
        row["status"] = (seen.get(k["id"]) or {}).get("status", "missing")
        row.pop("reason", None)
    for c in cls["equivalent"]:
        final[c["id"]]["status"] = "equivalent"
        final[c["id"]]["reason"] = c["reason"]
    for c in cls["invalid"]:
        final.pop(c["id"], None)
    for c in cls["defect"]:
        final[c["id"]]["status"] = "defect"
    targets = load(ROOT / "docs/specs/mut-m9-m14-probes/targets.json")
    tkey = {(t["milestone"], t["file"]): t for t in targets}
    per = {}
    for m in final.values():
        st = m.get("status")
        if st not in ("killed", "killed_new", "equivalent", "defect"):
            fails.append(f"{m['id']}: final status {st!r}")
        if st == "equivalent":
            reason = (m.get("reason") or "").strip()
            if len(reason) < 20 or REASON_BAN.search(reason):
                fails.append(f"{m['id']}: equivalent reason {reason[:80]!r} is about the tests, not the code - a survivor")
        key = (m.get("milestone"), m.get("file"))
        if key not in tkey:
            fails.append(f"{m['id']}: {key} is not a target of targets.json")
            continue
        per.setdefault(key, []).append(m)
    for key, t in tkey.items():
        ms = [m for m in per.get(key, []) if m["status"] != "defect"]
        real = [m for m in ms if m["status"] in ("killed", "killed_new")]
        eq = [m for m in ms if m["status"] == "equivalent"]
        if len(real) < t["min_mutants"]:
            fails.append(f"{key}: {len(real)} killed mutants, at least {t['min_mutants']} required")
        if ms and len(eq) * 5 > len(ms):
            fails.append(f"{key}: {len(eq)} of {len(ms)} mutants equivalent (> 20%)")
    counts = {s: sum(1 for m in final.values() if m.get("status") == s)
              for s in ("killed", "killed_new", "equivalent", "defect")}
    print(f"mutants: {len(final)} {counts}; kill table {len(kill_ids)}")

for f in fails:
    print("FAIL:", f)
if fails:
    sys.exit(1)
print(f"MUTB {MODE.upper()} PASS")
