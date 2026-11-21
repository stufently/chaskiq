#!/usr/bin/env python3
"""Probe for mut-r5b2 (new mutants of the production code the R5b-2 specs cover).

Usage (from the repo root):
  python3 -I docs/specs/mut-r5b2-probes/mutr_probe.py scope <BASE_SHA>
  python3 -I docs/specs/mut-r5b2-probes/mutr_probe.py scan <BASE_SHA>
  python3 -I docs/specs/mut-r5b2-probes/mutr_probe.py check <BASE_SHA>
  python3 -I docs/specs/mut-r5b2-probes/mutr_probe.py jobs        (used by mutr_kill_gate.sh)

Inputs next to this file: kill_table.json (mutants to kill, patches in patches/) and classified.json
(equivalent mutants the coordinator excluded up front, with the reason from the code).
The executor writes tmp/mutants-r5b2/manifest.json (untracked, never committed):
  {"mutants": [{"id": "R01", "status": "killed|killed_new", "specs": ["spec/..._spec.rb", ...],
                "test_added": "spec/..._spec.rb" (killed_new only)}]}

scope: the only changes against BASE are added or modified regular files under spec/; every commit of
  BASE..HEAD (first parent, no merges) too; nothing outside spec/ differs from BASE in HEAD or the work
  tree; no untracked file except report.json, report-blocked.md; no ignored-but-present .rspec* or
  file under app/, lib/, config/, spec/, vendor/nightfury, vendor/php_serialize.
scan: no added line under spec/ (diff BASE -> work tree, plus untracked spec files) reads source as
  text: Rails.root, File/IO/Dir/Pathname/FileUtils/Tempfile calls, a string path to an .rb file under
  app/ lib/ config/ vendor/ db/, source_location, .source, RubyVM, Ripper, Prism, method_source,
  __FILE__, __dir__, ObjectSpace, Kernel#open/system/spawn/exec/Open3/%x/backticks. A kill must be
  behavioural (calls, results, rows, errors, doubles/spies), never an inspection of the code.
check: the executor manifest has exactly the ids of kill_table.json, each killed or killed_new (any
  other status - blocked, survived, equivalent - is a failure), specs = existing spec files,
  killed_new: test_added listed in specs and changed since BASE; no excluded (classified.json) id
  is in the kill table.
jobs: prints the jobs for mutr_kill.rb - every kill-table mutant listed in the executor manifest, with
  the patch of this directory and the manifest's specs / test_added (exit 1 if the manifest is
  unreadable; missing ids are skipped - mutr_kill_gate.sh without --only then fails on the count).
Prints one "FAIL:" line per problem and "MUTR SCOPE PASS" / "MUTR SCAN PASS" / "MUTR CHECK PASS".
"""
import json
import pathlib
import re
import subprocess
import sys

args = sys.argv[1:]
if not args or args[0] not in ("scope", "scan", "check", "jobs") or (args[0] != "jobs" and len(args) != 2):
    sys.exit("usage: mutr_probe.py scope|scan|check <BASE_SHA> | jobs")
MODE = args[0]
BASE = args[1] if len(args) > 1 else None
ROOT = pathlib.Path(subprocess.run(["git", "rev-parse", "--show-toplevel"], check=True,
                                   capture_output=True, text=True).stdout.strip())
HERE = pathlib.Path(__file__).resolve().parent
UNTRACKED_OK = {"report.json", "report-blocked.md"}
MANIFEST = ROOT / "tmp" / "mutants-r5b2" / "manifest.json"
SOURCE_READ = [
    (re.compile(r"Rails\s*\.\s*root"), "Rails.root"),
    (re.compile(r"\b(File|IO|Dir|Pathname|FileUtils|Tempfile)\s*(\.|\[|::|\()"), "file/IO access"),
    (re.compile(r"""["'](\./)?(app|lib|config|vendor|db)/[^"']*\.rb\b"""), "path to a source file"),
    (re.compile(r"source_location|\.source\b|RubyVM|Ripper|\bPrism\b|method_source|MethodSource"),
     "source introspection"),
    (re.compile(r"__FILE__|__dir__|ObjectSpace"), "file/object introspection"),
    (re.compile(r"\b(Kernel\s*\.\s*)?(open|system|spawn|exec)\s*[\(\"']|\bOpen3\b|%x|`"), "shell/open"),
]
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
    rows = load(MANIFEST, "mutants")
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
            fails.append(f"{mid}: missing from tmp/mutants-r5b2/manifest.json")
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
elif MODE == "scan":
    added = []  # (file, line)
    cur = None
    for line in git("diff", "-U0", "--no-color", "--no-renames", BASE, "--", "spec").stdout.splitlines():
        if line.startswith("+++ "):
            cur = line[6:] if line.startswith("+++ b/") else None
        elif line.startswith("+") and cur:
            added.append((cur, line[1:]))
    for p in git("ls-files", "--others", "--exclude-standard", "--", "spec").stdout.splitlines():
        try:
            added += [(p, ln) for ln in (ROOT / p).read_text(encoding="utf-8", errors="replace").splitlines()]
        except OSError as e:
            fails.append(f"{p}: unreadable ({e})")
    files = set()
    for path, text in added:
        files.add(path)
        for rx, what in SOURCE_READ:
            if rx.search(text):
                fails.append(f"{path}: {what}: {text.strip()[:120]} (source inspection is not a kill)")
                break
    print(f"scanned {len(added)} added lines in {len(files)} spec files")
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
    excluded = {c["id"] for c in load(HERE / "classified.json", "equivalent")}
    for mid in sorted(excluded & set(kill_ids)):
        fails.append(f"{mid}: classified equivalent and in the kill table")
    changed_specs = set(git("diff", "--name-only", BASE, "--", "spec").stdout.split())
    for mid, r in seen.items():
        if mid not in kill_ids:
            continue
        st = r.get("status")
        if st not in ("killed", "killed_new"):
            why = (r.get("note") or r.get("reason") or "")[:80]
            fails.append(f"{mid}: status {st!r} {why!r} - every kill-table mutant must be killed (doubt -> section 9)")
        specs = r.get("specs") or []
        if not specs or any(not re.match(r"^spec/.*_spec\.rb$", s) or not (ROOT / s).is_file() for s in specs):
            fails.append(f"{mid}: specs missing or not existing spec files: {specs}")
        if st == "killed_new":
            ta = r.get("test_added") or ""
            if ta not in changed_specs or ta not in specs:
                fails.append(f"{mid}: test_added {ta!r} is not a spec file changed since BASE listed in specs")
    counts = {s: sum(1 for r in seen.values() if r.get("status") == s) for s in ("killed", "killed_new")}
    print(f"mutants: {len(kill_ids)} in the kill table, {len(excluded)} excluded as equivalent; manifest {counts}")

for f in fails:
    print("FAIL:", f)
if fails:
    sys.exit(1)
print(f"MUTR {MODE.upper()} PASS")
