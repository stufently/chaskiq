#!/usr/bin/env python3
"""Commit-by-commit probe for fork-updates-r2 ("one cop at a time").

Usage (from the repo root): python3 -I docs/specs/fork-updates-r2-probes/r2_commits_probe.py <BASE_SHA>

The commits BASE..HEAD (first parent, no merges) must be exactly, in this order:
  1. "Drop R2 cops from RuboCop todo"      - changes only .rubocop_todo.yml;
  2. "Autocorrect <cop>" for every cop of R2_COPS in r2_equiv_probe.py, in that order - each one
     non-empty, changes only Ruby files that BASE's .rubocop_todo.yml lists under that cop (or under
     a cop whose CASCADES lead to it), and r2_canon.rb on parent -> commit says SAME or EXPLAINED
     by that cop alone for every changed file (no DIFF, LINES, NEWWARN, ERROR);
  3. "Note fork-updates-r2 in changelog"   - changes only CHANGELOG.md;
  4. after it, only commits that change CHANGELOG.md alone (review wording fixes).
Prints one line per commit and "R2 COMMITS PASS" when everything holds.
"""
import ast
import pathlib
import shutil
import subprocess
import sys

if len(sys.argv) != 2:
    sys.exit("usage: r2_commits_probe.py <BASE_SHA>")
BASE = sys.argv[1]
ROOT = pathlib.Path(subprocess.run(["git", "rev-parse", "--show-toplevel"], check=True,
                                   capture_output=True, text=True).stdout.strip())
HERE = pathlib.Path(__file__).resolve().parent
tree = ast.parse((HERE / "r2_equiv_probe.py").read_text(encoding="utf-8"))


def const(name):
    return next(ast.literal_eval(n.value) for n in tree.body
                if isinstance(n, ast.Assign) and getattr(n.targets[0], "id", "") == name)


R2_COPS, CASCADES = const("R2_COPS"), const("CASCADES")
fails = []


def git(*args, binary=False):
    r = subprocess.run(["git", "-C", str(ROOT), *args], capture_output=True, text=not binary)
    if r.returncode != 0:
        sys.exit(f"FAIL: git {' '.join(args)}: {r.stderr if not binary else r.stderr.decode()}")
    return r.stdout


todo = {}
cop = None
for line in git("show", f"{BASE}:.rubocop_todo.yml").splitlines():
    if line[:1].isupper() and line.endswith(":") and "/" in line:
        cop = line[:-1]
        todo[cop] = set()
    elif line.startswith("    - '") and cop:
        todo[cop].add(line[7:].rstrip("'"))


def allowed_files(c):
    files = set(todo.get(c, set()))
    for src, extras in CASCADES.items():
        if c in extras:
            files |= todo.get(src, set())
    return files


commits = git("rev-list", "--reverse", "--first-parent", "--no-merges", f"{BASE}..HEAD").split()
merges = git("rev-list", "--merges", f"{BASE}..HEAD").split()
if merges:
    fails.append(f"merge commits in BASE..HEAD: {merges[:3]}")
expected = ["Drop R2 cops from RuboCop todo"] + [f"Autocorrect {c}" for c in R2_COPS] + \
           ["Note fork-updates-r2 in changelog"]

ruby_version = (ROOT / ".ruby-version").read_text().strip()
image = f"chaskiq-ci-local:ruby-{ruby_version}-ubuntu-26.04"
uid = f"{subprocess.run(['id', '-u'], capture_output=True, text=True).stdout.strip()}:" \
      f"{subprocess.run(['id', '-g'], capture_output=True, text=True).stdout.strip()}"
work = ROOT / "tmp" / "r2-commits"
shutil.rmtree(work, ignore_errors=True)


def canon_commit(sha, files, c):
    d = work / sha[:12]
    for side, rev in (("parent", f"{sha}^"), ("commit", sha)):
        for f in files:
            dst = d / side / f
            dst.parent.mkdir(parents=True, exist_ok=True)
            dst.write_bytes(git("show", f"{rev}:{f}", binary=True))
    (d / "list").write_text("".join(f"{f}\t{c}\n" for f in files))
    rel = d.relative_to(ROOT)
    cmd = ["docker", "run", "--rm", "--user", uid, "-e", "HOME=/tmp", "-v", f"{ROOT}:/app:ro",
           "-v", f"{HERE / 'r2_canon.rb'}:/r2_canon.rb:ro", "-w", "/app", image,
           "ruby", "/r2_canon.rb", f"/app/{rel}/parent", f"/app/{rel}/commit", f"/app/{rel}/list"]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        fails.append(f"r2_canon.rb exited {r.returncode}: {r.stderr.strip()[:300]}")
    return r.stdout.splitlines()


for i, sha in enumerate(commits):
    subject = git("log", "-1", "--format=%s", sha).strip()
    files = [f for f in git("diff-tree", "--no-commit-id", "--name-only", "-r", "--no-renames", sha).splitlines() if f]
    want = expected[i] if i < len(expected) else None
    if want is None:
        if files != ["CHANGELOG.md"]:
            fails.append(f"{sha[:12]} {subject!r}: extra commit after the changelog commit changes {files[:5]} "
                         f"(only CHANGELOG.md allowed)")
        print(f"{sha[:12]} {subject} (changelog fix)")
        continue
    if subject != want:
        fails.append(f"{sha[:12]}: subject {subject!r}, expected {want!r} (commit #{i + 1})")
        continue
    if want.startswith("Drop "):
        if files != [".rubocop_todo.yml"]:
            fails.append(f"{sha[:12]} {subject!r}: changes {files[:5]}, only .rubocop_todo.yml allowed")
    elif want.startswith("Note "):
        if files != ["CHANGELOG.md"]:
            fails.append(f"{sha[:12]} {subject!r}: changes {files[:5]}, only CHANGELOG.md allowed")
    else:
        c = want[len("Autocorrect "):]
        if not files:
            fails.append(f"{sha[:12]} {subject!r}: empty commit")
        outside = [f for f in files if f not in allowed_files(c)]
        if outside:
            fails.append(f"{sha[:12]} {subject!r}: files not listed under {c} at BASE: {outside[:5]}")
        verdicts = canon_commit(sha, [f for f in files if f not in outside], c) if files else []
        for v in verdicts:
            parts = v.split()
            if parts[0] == "SAME" or (parts[0] == "EXPLAINED" and parts[2:] == [c]):
                continue
            fails.append(f"{sha[:12]} {subject!r}: {v}")
    print(f"{sha[:12]} {subject} ({len(files)} files)")

if len(commits) < len(expected):
    fails.append(f"missing commits: {expected[len(commits):]}")
for f in fails:
    print("FAIL:", f)
if fails:
    sys.exit(1)
print("R2 COMMITS PASS")
