#!/usr/bin/env python3
"""Commit-by-commit probe for fork-updates-r3.

Usage (from the repo root): python3 -I docs/specs/fork-updates-r3-probes/r3_commits_probe.py <BASE_SHA>

The commits BASE..HEAD (first parent, no merges) must be exactly, in this order:
  1. "Drop R3 cops from RuboCop todo"                  - changes only .rubocop_todo.yml;
  2. "Autocorrect Style/FrozenStringLiteralComment"    - changes exactly FSL_FILES (the BASE todo
     list of the cop minus NOT_INSPECTED, from r3_equiv_probe.py); for each file r3_frozen.rb
     `shape` on parent -> commit says SAME (text = parent + comment + blank line, AST unchanged);
  3. "Autocorrect Style/RedundantFreeze"               - changes exactly FREEZE_FILES; for each file
     r3_frozen.rb `freeze` on parent -> commit says EXPLAINED;
  4. "Note fork-updates-r3 in changelog"               - changes only CHANGELOG.md;
  5. after it, only commits that change CHANGELOG.md alone (review wording fixes).
Every commit keeps the git mode of every path it touches (100644/100755 as in the parent, no type
change, no added/deleted path). Every commit that touches CHANGELOG.md leaves it as BASE's file with
one non-empty block inserted right after the "# Changelog" line (BASE's text below it byte for byte),
and the block mentions fork-updates-r3.
Prints one line per commit and "R3 COMMITS PASS" when everything holds.
"""
import ast
import pathlib
import shutil
import subprocess
import sys

if len(sys.argv) != 2:
    sys.exit("usage: r3_commits_probe.py <BASE_SHA>")
BASE = sys.argv[1]
ROOT = pathlib.Path(subprocess.run(["git", "rev-parse", "--show-toplevel"], check=True,
                                   capture_output=True, text=True).stdout.strip())
HERE = pathlib.Path(__file__).resolve().parent
tree = ast.parse((HERE / "r3_equiv_probe.py").read_text(encoding="utf-8"))


def const(name):
    return next(ast.literal_eval(n.value) for n in tree.body
                if isinstance(n, ast.Assign) and getattr(n.targets[0], "id", "") == name)


COP, NOT_INSPECTED, FREEZE_FILES = const("COP"), const("NOT_INSPECTED"), const("FREEZE_FILES")
fails = []


def git(*args, binary=False):
    r = subprocess.run(["git", "-C", str(ROOT), *args], capture_output=True, text=not binary)
    if r.returncode != 0:
        err = r.stderr if not binary else r.stderr.decode()
        print(f"FAIL: git {' '.join(args)}: {err.strip()[:300]}")
        sys.exit(1)
    return r.stdout


listed, cur = [], None
for line in git("show", f"{BASE}:.rubocop_todo.yml").splitlines():
    if line[:1].isupper() and line.endswith(":") and "/" in line:
        cur = line[:-1]
    elif line.startswith("    - '") and cur == COP:
        listed.append(line[7:].rstrip("'"))
FSL_FILES = sorted(p for p in listed if p not in NOT_INSPECTED)
if not FSL_FILES:
    fails.append(f"{COP} absent from BASE .rubocop_todo.yml (spec defect)")

commits = git("rev-list", "--reverse", "--first-parent", "--no-merges", f"{BASE}..HEAD").split()
merges = git("rev-list", "--merges", f"{BASE}..HEAD").split()
if merges:
    fails.append(f"merge commits in BASE..HEAD: {merges[:3]}")
expected = ["Drop R3 cops from RuboCop todo", f"Autocorrect {COP}", "Autocorrect Style/RedundantFreeze",
            "Note fork-updates-r3 in changelog"]
image = f"chaskiq-ci-local:ruby-{(ROOT / '.ruby-version').read_text().strip()}-ubuntu-26.04"
uid = f"{subprocess.run(['id', '-u'], capture_output=True, text=True).stdout.strip()}:" \
      f"{subprocess.run(['id', '-g'], capture_output=True, text=True).stdout.strip()}"
work = ROOT / "tmp" / "r3-commits"
shutil.rmtree(work, ignore_errors=True)


def check(sha, files, mode, want):
    d = work / sha[:12]
    for side, rev in (("parent", f"{sha}^"), ("commit", sha)):
        for f in files:
            dst = d / side / f
            dst.parent.mkdir(parents=True, exist_ok=True)
            dst.write_bytes(git("show", f"{rev}:{f}", binary=True))
    (d / "list").write_text("".join(f"{f}\n" for f in files))
    rel = d.relative_to(ROOT)
    cmd = ["docker", "run", "--rm", "--user", uid, "-e", "HOME=/tmp", "-v", f"{ROOT}:/app:ro",
           "-v", f"{HERE / 'r3_frozen.rb'}:/r3_frozen.rb:ro", "-w", "/app", image, "ruby", "/r3_frozen.rb",
           mode, f"/app/{rel}/parent", f"/app/{rel}/commit", f"/app/{rel}/list"]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        fails.append(f"r3_frozen.rb exited {r.returncode}: {r.stderr.strip()[:300]}")
    seen = set()
    for v in r.stdout.splitlines():
        parts = v.split()
        seen.add(parts[1] if len(parts) > 1 else "")
        if parts[0] != want:
            fails.append(f"{sha[:12]}: {v[:250]} (expected {want})")
    if seen != set(files):
        fails.append(f"{sha[:12]}: r3_frozen.rb gave no verdict for {sorted(set(files) - seen)[:5]}")


base_cl = git("show", f"{BASE}:CHANGELOG.md")
HEADER = "# Changelog\n"
if not base_cl.startswith(HEADER):
    fails.append("BASE CHANGELOG.md does not start with '# Changelog' (spec defect)")


def changelog_ok(sha):
    cur = git("show", f"{sha}:CHANGELOG.md")
    rest = base_cl[len(HEADER):]
    if not cur.startswith(HEADER) or not cur.endswith(rest) or len(cur) < len(base_cl):
        return "CHANGELOG.md is not BASE with a block inserted after '# Changelog' (BASE text changed)"
    block = cur[len(HEADER):len(cur) - len(rest)]
    if not block.strip():
        return "no changelog entry added"
    if "fork-updates-r3" not in block:
        return "the added changelog block does not mention fork-updates-r3"
    return None


for i, sha in enumerate(commits):
    subject = git("log", "-1", "--format=%s", sha).strip()
    for line in git("diff-tree", "--raw", "-r", "--no-renames", "--no-commit-id", sha).splitlines():
        parts = line.split("\t", 1)
        meta = parts[0].split()
        if len(meta) < 5 or len(parts) < 2:
            continue
        old_mode, new_mode, status = meta[0].lstrip(":"), meta[1], meta[4]
        if status in ("A", "D", "T") or old_mode != new_mode or new_mode not in ("100644", "100755"):
            fails.append(f"{sha[:12]} {subject!r}: {parts[1]}: mode {old_mode} -> {new_mode} (status {status}); "
                         f"only content edits of regular files")
    touched = git("diff-tree", "--no-commit-id", "--name-only", "-r", "--no-renames", sha).split()
    if "CHANGELOG.md" in touched and (why := changelog_ok(sha)):
        fails.append(f"{sha[:12]} {subject!r}: {why}")
    files = sorted(f for f in git("diff-tree", "--no-commit-id", "--name-only", "-r", "--no-renames", sha).splitlines() if f)
    want = expected[i] if i < len(expected) else None
    print(f"{sha[:12]} {subject} ({len(files)} files)")
    if want is None:
        if files != ["CHANGELOG.md"]:
            fails.append(f"{sha[:12]} {subject!r}: extra commit after the changelog commit changes {files[:5]} "
                         f"(only CHANGELOG.md allowed)")
        continue
    if subject != want:
        fails.append(f"{sha[:12]}: subject {subject!r}, expected {want!r} (commit #{i + 1})")
        continue
    if i == 0 and files != [".rubocop_todo.yml"]:
        fails.append(f"{sha[:12]} {subject!r}: changes {files[:5]}, only .rubocop_todo.yml allowed")
    elif i == 3 and files != ["CHANGELOG.md"]:
        fails.append(f"{sha[:12]} {subject!r}: changes {files[:5]}, only CHANGELOG.md allowed")
    elif i in (1, 2):
        allowed = FSL_FILES if i == 1 else sorted(FREEZE_FILES)
        if files != allowed:
            extra, missing = sorted(set(files) - set(allowed)), sorted(set(allowed) - set(files))
            fails.append(f"{sha[:12]} {subject!r}: files differ from the declared list: extra {extra[:5]}, "
                         f"missing {missing[:5]}")
        ok = [f for f in files if f in allowed]
        if ok:
            check(sha, ok, "shape" if i == 1 else "freeze", "SAME" if i == 1 else "EXPLAINED")

if len(commits) < len(expected):
    fails.append(f"missing commits: {expected[len(commits):]}")
for f in fails:
    print("FAIL:", f)
if fails:
    sys.exit(1)
print("R3 COMMITS PASS")
