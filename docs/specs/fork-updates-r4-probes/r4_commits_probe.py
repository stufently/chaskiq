#!/usr/bin/env python3
"""Commit-by-commit probe for fork-updates-r4.

Usage (from the repo root): python3 -I docs/specs/fork-updates-r4-probes/r4_commits_probe.py <BASE_SHA>

The commits BASE..HEAD (first parent, no merges) must be exactly, in this order:
  1. "Drop R4 cop from RuboCop todo"               - changes only .rubocop_todo.yml, which equals
     expected_todo(BASE) of r4_equiv_probe.py (the cop's list cut down to KEEP);
  2. "Autocorrect Style/ClassAndModuleChildren"   - changes exactly R4_FILES (BASE todo list of the
     cop minus KEEP); r4_nest.rb `shape` on parent -> commit says SAME for each;
  3. "Note fork-updates-r4 in changelog"           - changes only CHANGELOG.md;
  4. after it, only commits that change CHANGELOG.md alone.
Every commit keeps the git mode of every path it touches (no type change, no add/delete). Every
commit that touches CHANGELOG.md leaves it as BASE's file with one non-empty block inserted right
after the "# Changelog" line (BASE's text below it byte for byte) that mentions fork-updates-r4.
Prints one line per commit and "R4 COMMITS PASS".
"""
import ast
import os
import pathlib
import re
import shutil
import subprocess
import sys

if len(sys.argv) != 2:
    sys.exit("usage: r4_commits_probe.py <BASE_SHA>")
BASE = sys.argv[1]
ROOT = pathlib.Path(subprocess.run(["git", "rev-parse", "--show-toplevel"], check=True,
                                   capture_output=True, text=True).stdout.strip())
HERE = pathlib.Path(__file__).resolve().parent
src = (HERE / "r4_equiv_probe.py").read_text(encoding="utf-8")
tree = ast.parse(src)
ns = {"re": re}
for n in tree.body:
    if (isinstance(n, ast.Assign) and getattr(n.targets[0], "id", "") in ("COP", "KEEP")) or \
       (isinstance(n, ast.FunctionDef) and n.name in ("todo_list", "expected_todo")):
        exec(compile(ast.Module([n], []), "r4_equiv_probe.py", "exec"), ns)
COP, KEEP = ns["COP"], ns["KEEP"]
HEADER = "# Changelog\n"
fails = []


def git(*a, binary=False):
    r = subprocess.run(["git", "-C", str(ROOT), *a], capture_output=True, text=not binary)
    if r.returncode != 0:
        print(f"FAIL: git {' '.join(a)}: {(r.stderr if not binary else r.stderr.decode()).strip()[:300]}")
        sys.exit(1)
    return r.stdout


base_todo = git("show", f"{BASE}:.rubocop_todo.yml")
base_cl = git("show", f"{BASE}:CHANGELOG.md")
R4_FILES = sorted(p for p in ns["todo_list"](base_todo, COP) if p not in KEEP)
want_todo = ns["expected_todo"](base_todo)
if not R4_FILES:
    fails.append(f"{COP} absent from BASE .rubocop_todo.yml (spec defect)")


def changelog_ok(cur):
    rest = base_cl[len(HEADER):]
    if not base_cl.startswith(HEADER):
        return "BASE CHANGELOG.md does not start with '# Changelog' (spec defect)"
    if not cur.startswith(HEADER) or not cur.endswith(rest) or len(cur) < len(base_cl):
        return "CHANGELOG.md is not BASE with a block inserted after '# Changelog' (BASE text changed)"
    block = cur[len(HEADER):len(cur) - len(rest)]
    if not block.strip():
        return "no changelog entry added"
    if "fork-updates-r4" not in block:
        return "the added changelog block does not mention fork-updates-r4"
    return None


image = f"chaskiq-ci-local:ruby-{(ROOT / '.ruby-version').read_text().strip()}-ubuntu-26.04"
work = ROOT / "tmp" / "r4-commits"
shutil.rmtree(work, ignore_errors=True)


def shape(sha, files):
    d = work / sha[:12]
    for side, rev in (("parent", f"{sha}^"), ("commit", sha)):
        for f in files:
            dst = d / side / f
            dst.parent.mkdir(parents=True, exist_ok=True)
            dst.write_bytes(git("show", f"{rev}:{f}", binary=True))
    (d / "list").write_text("".join(f"{f}\n" for f in files))
    rel = d.relative_to(ROOT)
    r = subprocess.run(["docker", "run", "--rm", "--user", f"{os.getuid()}:{os.getgid()}", "-e", "HOME=/tmp",
                        "-v", f"{ROOT}:/app:ro", "-v", f"{HERE / 'r4_nest.rb'}:/r4_nest.rb:ro", "-w", "/app", image,
                        "ruby", "/r4_nest.rb", "shape", f"/app/{rel}/parent", f"/app/{rel}/commit", f"/app/{rel}/list"],
                       capture_output=True, text=True)
    if r.returncode != 0:
        fails.append(f"r4_nest.rb exited {r.returncode}: {r.stderr.strip()[:300]}")
    seen = set()
    for v in r.stdout.splitlines():
        parts = v.split()
        seen.add(parts[1] if len(parts) > 1 else "")
        if parts[0] != "SAME":
            fails.append(f"{sha[:12]}: {v[:250]}")
    if seen != set(files):
        fails.append(f"{sha[:12]}: no verdict for {sorted(set(files) - seen)[:5]}")


expected = ["Drop R4 cop from RuboCop todo", f"Autocorrect {COP}", "Note fork-updates-r4 in changelog"]
commits = git("rev-list", "--reverse", "--first-parent", "--no-merges", f"{BASE}..HEAD").split()
if git("rev-list", "--merges", f"{BASE}..HEAD").split():
    fails.append("merge commits in BASE..HEAD")
for i, sha in enumerate(commits):
    subject = git("log", "-1", "--format=%s", sha).strip()
    files = sorted(f for f in git("diff-tree", "--no-commit-id", "--name-only", "-r", "--no-renames", sha).split() if f)
    print(f"{sha[:12]} {subject} ({len(files)} files)")
    for line in git("diff-tree", "--raw", "-r", "--no-renames", "--no-commit-id", sha).splitlines():
        parts = line.split("\t", 1)
        meta = parts[0].split()
        if len(meta) >= 5 and len(parts) == 2:
            old, new, status = meta[0].lstrip(":"), meta[1], meta[4]
            if status in ("A", "D", "T") or old != new or new not in ("100644", "100755"):
                fails.append(f"{sha[:12]} {subject!r}: {parts[1]}: mode {old} -> {new} (status {status})")
    if "CHANGELOG.md" in files and (why := changelog_ok(git("show", f"{sha}:CHANGELOG.md"))):
        fails.append(f"{sha[:12]} {subject!r}: {why}")
    want = expected[i] if i < len(expected) else None
    if want is None:
        if files != ["CHANGELOG.md"]:
            fails.append(f"{sha[:12]} {subject!r}: extra commit after the changelog commit changes {files[:5]}")
        continue
    if subject != want:
        fails.append(f"{sha[:12]}: subject {subject!r}, expected {want!r} (commit #{i + 1})")
        continue
    if i == 0:
        if files != [".rubocop_todo.yml"]:
            fails.append(f"{sha[:12]} {subject!r}: changes {files[:5]}, only .rubocop_todo.yml allowed")
        elif git("show", f"{sha}:.rubocop_todo.yml") != want_todo:
            fails.append(f"{sha[:12]}: .rubocop_todo.yml is not the expected text")
    elif i == 1:
        if files != R4_FILES:
            fails.append(f"{sha[:12]} {subject!r}: files differ from R4_FILES: extra {sorted(set(files) - set(R4_FILES))[:5]}, "
                         f"missing {sorted(set(R4_FILES) - set(files))[:5]}")
        ok = [f for f in files if f in R4_FILES]
        if ok:
            shape(sha, ok)
    elif files != ["CHANGELOG.md"]:
        fails.append(f"{sha[:12]} {subject!r}: changes {files[:5]}, only CHANGELOG.md allowed")
if len(commits) < len(expected):
    fails.append(f"missing commits: {expected[len(commits):]}")
for f in fails:
    print("FAIL:", f)
if fails:
    sys.exit(1)
print("R4 COMMITS PASS")
