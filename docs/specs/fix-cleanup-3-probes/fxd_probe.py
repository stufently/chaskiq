#!/usr/bin/env python3
"""Tree and commit probe for fix-cleanup-3 (two Lead#verify! behaviour fixes, no RuboCop cop).

Usage (from the repo root):
  python3 -I docs/specs/fix-cleanup-3-probes/fxd_probe.py tree <BASE_SHA>
  python3 -I docs/specs/fix-cleanup-3-probes/fxd_probe.py commits <BASE_SHA>

Everything comes from fxd_config.json next to this file.

tree - the working tree against BASE:
  1. changed paths: exactly the app files, the fix spec files (all new: status A, mode
     100644) and CHANGELOG.md - each of them changed, nothing else (.rubocop_todo.yml and
     .rubocop.yml unchanged); no untracked file; no ignored-but-present .rspec* or file under app/,
     lib/, config/, spec/;
  2. every app file is byte for byte BASE with the two patches applied in order (fxd_type,
     fxd_order);
  3. no `rubocop:` directive in any added line.
commits - BASE..HEAD (first parent, no merges) is exactly the commit list of fxd_config.json, in
  order: each test commit adds exactly its fix spec and leaves the app code as it was (BASE + the
  patches before it); each fix commit applies exactly its patch and adds nothing; the changelog
  commit and any later commit change only CHANGELOG.md, which is BASE with one block after
  "# Changelog" that mentions fix-cleanup-3 and has at least two "- Fixed:" entries.
  No commit changes a git mode, deletes or retypes a path.
Prints "FXD TREE PASS" / "FXD COMMITS PASS" or one "FAIL:" line per problem.
"""
import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile

if len(sys.argv) != 3 or sys.argv[1] not in ("tree", "commits"):
    sys.exit("usage: fxd_probe.py tree|commits <BASE_SHA>")
MODE, BASE = sys.argv[1], sys.argv[2]
ROOT = pathlib.Path(subprocess.run(["git", "rev-parse", "--show-toplevel"], check=True,
                                   capture_output=True, text=True).stdout.strip())
HERE = pathlib.Path(__file__).resolve().parent
CFG = json.loads((HERE / "fxd_config.json").read_text(encoding="utf-8"))
APP, FIX = CFG["app_files"], [f["file"] for f in CFG["fix_specs"]]
PATCHES = [c["patch"] for c in CFG["commits"] if c["patch"]]
HEADER = "# Changelog\n"
fails = []


def git(*a, binary=False):
    r = subprocess.run(["git", "-C", str(ROOT), *a], capture_output=True, text=not binary)
    if r.returncode != 0:
        err = r.stderr if not binary else r.stderr.decode()
        print(f"FAIL: git {' '.join(a)}: {err.strip()[:300]}")
        sys.exit(1)
    return r.stdout


def stage(n):
    """App files after the first n patches applied to BASE: {path: bytes}."""
    with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as d:
        for f in APP:
            p = pathlib.Path(d) / f
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_bytes(git("show", f"{BASE}:{f}", binary=True))
        for patch in PATCHES[:n]:
            # tmp/ is inside the work tree: stop git from finding the repo, or `git apply` would
            # silently skip every path outside the cwd.
            r = subprocess.run(["git", "apply", "--whitespace=nowarn", str(HERE / patch)], cwd=d,
                               capture_output=True, text=True,
                               env={**os.environ, "GIT_CEILING_DIRECTORIES": str(ROOT / "tmp")})
            if r.returncode != 0:
                print(f"FAIL: {patch} does not apply to BASE (spec defect or wrong BASE): {r.stderr.strip()[:300]}")
                sys.exit(1)
        return {f: (pathlib.Path(d) / f).read_bytes() for f in APP}


def changelog_ok(cur, base_cl):
    rest = base_cl[len(HEADER):]
    if not base_cl.startswith(HEADER):
        return "BASE CHANGELOG.md does not start with '# Changelog' (spec defect)"
    if not cur.startswith(HEADER) or not cur.endswith(rest) or len(cur) < len(base_cl):
        return "CHANGELOG.md is not BASE with a block inserted after '# Changelog' (BASE text changed)"
    block = cur[len(HEADER):len(cur) - len(rest)]
    if not block.strip():
        return "no changelog entry added"
    if "fix-cleanup-3" not in block:
        return "the added changelog block does not mention fix-cleanup-3"
    if len(re.findall(r"(?m)^- Fixed: ", block)) < 2:
        return "the added changelog block has fewer than two '- Fixed: ' entries (one per fix)"
    return None


def raw(*a):
    """[(old_mode, new_mode, status, path)] of a diff --raw."""
    out = []
    for line in git(*a).splitlines():
        parts = line.split("\t", 1)
        meta = parts[0].split()
        if len(meta) >= 5 and len(parts) == 2:
            out.append((meta[0].lstrip(":"), meta[1], meta[4], parts[1]))
    return out


def modes_ok(rows, where, added):
    for old, new, status, p in rows:
        if p in added:
            if status != "A" or new != "100644":
                fails.append(f"{where}{p}: must be a new regular file (status {status}, mode {new})")
        elif status in ("A", "D", "T") or old != new or new not in ("100644", "100755"):
            fails.append(f"{where}{p}: mode {old} -> {new} (status {status}); only content edits allowed")


def directives(diff_text, where):
    for line in diff_text.splitlines():
        if line.startswith("+") and not line.startswith("+++") and re.search(r"rubocop\s*:", line, re.I):
            fails.append(f"{where}rubocop directive added: {line[:120]}")


(ROOT / "tmp").mkdir(exist_ok=True)
base_todo = git("show", f"{BASE}:.rubocop_todo.yml")
base_cl = git("show", f"{BASE}:CHANGELOG.md")
specs = FIX

if MODE == "tree":
    allowed = set(APP) | set(specs) | {"CHANGELOG.md"}
    rows = raw("diff", "--raw", "--no-renames", BASE)
    modes_ok(rows, "", set(specs))
    changed = {r[3] for r in rows}
    for p in sorted(changed - allowed):
        fails.append(f"{p}: changed, but not a fix-cleanup-3 path")
    missing = sorted(allowed - changed)
    if missing:
        fails.append(f"fix-cleanup-3 paths without the change: {missing}")
    untracked = [p for p in git("ls-files", "--others", "--exclude-standard").splitlines()
                 if p and p not in ("report.json", "report-blocked.md")]
    if untracked:
        fails.append(f"untracked files: {untracked[:10]}")
    for line in git("status", "--porcelain", "--ignored=matching", "--untracked-files=all").splitlines():
        p = line[3:]
        if line.startswith("!! ") and (re.match(r"^(\.rspec|(app|lib|config|spec)/)", p) or p.endswith(".rspec-local")):
            fails.append(f"{p}: ignored but present (affects the test run)")
    want = stage(len(PATCHES))
    for f in APP:
        if (ROOT / f).read_bytes() != want[f]:
            fails.append(f"{f}: is not BASE + {', '.join(PATCHES)} (spec section 5)")
    if (ROOT / ".rubocop_todo.yml").read_text(encoding="utf-8") != base_todo:
        fails.append(".rubocop_todo.yml changed (fix-cleanup-3 does not touch it)")
    if (ROOT / ".rubocop.yml").read_text(encoding="utf-8") != git("show", f"{BASE}:.rubocop.yml"):
        fails.append(".rubocop.yml changed (fix-cleanup-3 does not touch it)")
    directives(git("diff", "--no-renames", BASE), "")
    print(f"paths: {len(APP)} app files, {len(FIX)} fix spec files, CHANGELOG")
    for f in fails:
        print("FAIL:", f)
    sys.exit(1 if fails else print("FXD TREE PASS"))

# commits ----------------------------------------------------------------------------------------------
expected = CFG["commits"]
commits = git("rev-list", "--reverse", "--first-parent", "--no-merges", f"{BASE}..HEAD").split()
if git("rev-list", "--merges", f"{BASE}..HEAD").split():
    fails.append("merge commits in BASE..HEAD")
npatch = 0
stages = {}
for i, sha in enumerate(commits):
    subject = git("log", "-1", "--format=%s", sha).strip()
    rows = raw("diff-tree", "--raw", "-r", "--no-renames", "--no-commit-id", sha)
    files = sorted(r[3] for r in rows)
    print(f"{sha[:12]} {subject} ({len(files)} files)")
    want = expected[i] if i < len(expected) else None
    modes_ok(rows, f"{sha[:12]} ", set(want["added"]) if want else set())
    directives(git("show", "--format=", "--no-renames", sha), f"{sha[:12]} ")
    if "CHANGELOG.md" in files and (why := changelog_ok(git("show", f"{sha}:CHANGELOG.md"), base_cl)):
        fails.append(f"{sha[:12]} {subject!r}: {why}")
    if want is None:
        if files != ["CHANGELOG.md"]:
            fails.append(f"{sha[:12]} {subject!r}: extra commit after the changelog commit changes {files[:5]}")
        continue
    if subject != want["subject"]:
        fails.append(f"{sha[:12]}: subject {subject!r}, expected {want['subject']!r} (commit #{i + 1})")
        continue
    if want.get("changelog"):
        if files != ["CHANGELOG.md"]:
            fails.append(f"{sha[:12]} {subject!r}: changes {files[:5]}, only CHANGELOG.md allowed")
        continue
    if want["patch"]:
        npatch += 1
    exp_app = stages.setdefault(npatch, stage(npatch))
    app_changed = sorted(f for f in files if f in APP)
    should = sorted(f for f in APP if exp_app[f] != stages.setdefault(npatch - 1, stage(npatch - 1))[f]) \
        if want["patch"] else []
    if sorted(set(files) - set(app_changed)) != sorted(want["added"]) or app_changed != should:
        fails.append(f"{sha[:12]} {subject!r}: changes {files}, expected {sorted(should + want['added'])}")
    for f in APP:
        if git("show", f"{sha}:{f}", binary=True) != exp_app[f]:
            fails.append(f"{sha[:12]} {subject!r}: {f} is not BASE + {PATCHES[:npatch] or 'nothing'}")
            break
if len(commits) < len(expected):
    fails.append(f"missing commits: {[c['subject'] for c in expected[len(commits):]]}")
for f in fails:
    print("FAIL:", f)
sys.exit(1 if fails else print("FXD COMMITS PASS"))
