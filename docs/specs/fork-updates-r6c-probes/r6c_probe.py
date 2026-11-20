#!/usr/bin/env python3
"""Tree and commit probe for fork-updates-r6c (Lint offenses in spec/).

Usage (from the repo root):
  python3 -I docs/specs/fork-updates-r6c-probes/r6c_probe.py tree <BASE_SHA>
  python3 -I docs/specs/fork-updates-r6c-probes/r6c_probe.py commits <BASE_SHA>

Everything comes from r6c_config.json next to this file.

tree - the working tree against BASE:
  1. changed paths: exactly the spec files of the config (`files`; `deleted` among them are gone),
     .rubocop_todo.yml and CHANGELOG.md - each of them changed, nothing else; no untracked file; no
     ignored-but-present .rspec* or file under app/, lib/, config/, spec/;
  2. every spec file is byte for byte BASE with r6c_specs.patch applied (a deleted file is absent);
  3. .rubocop_todo.yml is BASE without the blocks of cops_whole and without the spec/ lines of the
     cops_partial blocks (a block left without any file line is dropped); .rubocop.yml unchanged;
  4. no `rubocop:` directive in any added line.
commits - BASE..HEAD (first parent, no merges) is exactly the commit list of the config, in order:
  the patch commit changes exactly the spec files (= BASE + patch), the todo commit only the todo
  (= expected text), the changelog commit and any later commit only CHANGELOG.md, which is BASE with
  one block after "# Changelog" that mentions fork-updates-r6c. Only `deleted` paths may be deleted;
  no commit changes a git mode or retypes a path.
Prints "R6C TREE PASS" / "R6C COMMITS PASS" or one "FAIL:" line per problem.
"""
import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile

if len(sys.argv) != 3 or sys.argv[1] not in ("tree", "commits"):
    sys.exit("usage: r6c_probe.py tree|commits <BASE_SHA>")
MODE, BASE = sys.argv[1], sys.argv[2]
ROOT = pathlib.Path(subprocess.run(["git", "rev-parse", "--show-toplevel"], check=True,
                                   capture_output=True, text=True).stdout.strip())
HERE = pathlib.Path(__file__).resolve().parent
CFG = json.loads((HERE / "r6c_config.json").read_text(encoding="utf-8"))
FILES, DELETED = CFG["files"], set(CFG["deleted"])
PATCH = CFG["patch"]
HEADER = "# Changelog\n"
fails = []


def git(*a, binary=False):
    r = subprocess.run(["git", "-C", str(ROOT), *a], capture_output=True, text=not binary)
    if r.returncode != 0:
        err = r.stderr if not binary else r.stderr.decode()
        print(f"FAIL: git {' '.join(a)}: {err.strip()[:300]}")
        sys.exit(1)
    return r.stdout


def patched():
    """Spec files after the patch applied to BASE: {path: bytes or None (deleted)}."""
    with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as d:
        for f in FILES:
            p = pathlib.Path(d) / f
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_bytes(git("show", f"{BASE}:{f}", binary=True))
        # tmp/ is inside the work tree: stop git from finding the repo, or `git apply` would
        # silently skip every path outside the cwd.
        r = subprocess.run(["git", "apply", "--whitespace=nowarn", str(HERE / PATCH)], cwd=d,
                           capture_output=True, text=True,
                           env={**os.environ, "GIT_CEILING_DIRECTORIES": str(ROOT / "tmp")})
        if r.returncode != 0:
            print(f"FAIL: {PATCH} does not apply to BASE (spec defect or wrong BASE): {r.stderr.strip()[:300]}")
            sys.exit(1)
        out = {}
        for f in FILES:
            p = pathlib.Path(d) / f
            out[f] = p.read_bytes() if p.exists() else None
        return out


def has_cop(block, cops):
    return any(re.search(rf"(?m)^{re.escape(c)}:$", block) for c in cops)


def expected_todo(text):
    head, *blocks = text.rstrip("\n").split("\n\n")
    keep = [b for b in blocks if not has_cop(b, CFG["cops_whole"])]
    if len(keep) != len(blocks) - len(CFG["cops_whole"]):
        fails.append("BASE todo does not have exactly one block per whole R6c cop (spec defect)")
    out = []
    for b in keep:
        if has_cop(b, CFG["cops_partial"]):
            lines = b.split("\n")
            gone = [ln for ln in lines if re.match(r"^    - 'spec/", ln)]
            for ln in gone:
                if ln[7:-1] not in FILES:
                    fails.append(f"BASE todo line {ln.strip()} is not an R6c spec file (spec defect)")
            b = "\n".join(ln for ln in lines if ln not in gone)
            if not re.search(r"(?m)^    - '", b):
                continue  # nothing left in this block (app/ entries already gone): drop it
        out.append(b)
    return "\n\n".join([head] + out) + "\n"


def changelog_ok(cur, base_cl):
    rest = base_cl[len(HEADER):]
    if not base_cl.startswith(HEADER):
        return "BASE CHANGELOG.md does not start with '# Changelog' (spec defect)"
    if not cur.startswith(HEADER) or not cur.endswith(rest) or len(cur) < len(base_cl):
        return "CHANGELOG.md is not BASE with a block inserted after '# Changelog' (BASE text changed)"
    block = cur[len(HEADER):len(cur) - len(rest)]
    if not block.strip():
        return "no changelog entry added"
    if "fork-updates-r6c" not in block:
        return "the added changelog block does not mention fork-updates-r6c"
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


def modes_ok(rows, where):
    for old, new, status, p in rows:
        if p in DELETED:
            if status != "D":
                fails.append(f"{where}{p}: must be deleted (status {status})")
        elif status in ("A", "D", "T") or old != new or new not in ("100644", "100755"):
            fails.append(f"{where}{p}: mode {old} -> {new} (status {status}); only content edits allowed")


def directives(diff_text, where):
    for line in diff_text.splitlines():
        if line.startswith("+") and not line.startswith("+++") and re.search(r"rubocop\s*:", line, re.I):
            fails.append(f"{where}rubocop directive added: {line[:120]}")


(ROOT / "tmp").mkdir(exist_ok=True)
base_todo = git("show", f"{BASE}:.rubocop_todo.yml")
base_cl = git("show", f"{BASE}:CHANGELOG.md")
want_todo = expected_todo(base_todo)
want = patched()

if MODE == "tree":
    allowed = set(FILES) | {".rubocop_todo.yml", "CHANGELOG.md"}
    rows = raw("diff", "--raw", "--no-renames", BASE)
    modes_ok(rows, "")
    changed = {r[3] for r in rows}
    for p in sorted(changed - allowed):
        fails.append(f"{p}: changed, but not an R6c path")
    missing = sorted(allowed - changed)
    if missing:
        fails.append(f"R6c paths without the change: {missing}")
    untracked = [p for p in git("ls-files", "--others", "--exclude-standard").splitlines()
                 if p and p not in ("report.json", "report-blocked.md")]
    if untracked:
        fails.append(f"untracked files: {untracked[:10]}")
    for line in git("status", "--porcelain", "--ignored=matching", "--untracked-files=all").splitlines():
        p = line[3:]
        if line.startswith("!! ") and (re.match(r"^(\.rspec|(app|lib|config|spec)/)", p) or p.endswith(".rspec-local")):
            fails.append(f"{p}: ignored but present (affects the test run)")
    for f in FILES:
        path = ROOT / f
        if want[f] is None:
            if path.exists():
                fails.append(f"{f}: must be deleted ({PATCH})")
        elif not path.exists() or path.read_bytes() != want[f]:
            fails.append(f"{f}: is not BASE + {PATCH} (spec section 5)")
    if (ROOT / ".rubocop_todo.yml").read_text(encoding="utf-8") != want_todo:
        fails.append(".rubocop_todo.yml is not BASE without the R6c entries (blocks of "
                     + ", ".join(CFG["cops_whole"]) + "; spec/ lines of " + ", ".join(CFG["cops_partial"]) + ")")
    if (ROOT / ".rubocop.yml").read_text(encoding="utf-8") != git("show", f"{BASE}:.rubocop.yml"):
        fails.append(".rubocop.yml changed (R6c does not touch it)")
    directives(git("diff", "--no-renames", BASE), "")
    print(f"paths: {len(FILES)} spec files ({len(DELETED)} deleted), todo, CHANGELOG")
    for f in fails:
        print("FAIL:", f)
    sys.exit(1 if fails else print("R6C TREE PASS"))

# commits ----------------------------------------------------------------------------------------------
expected = CFG["commits"]
commits = git("rev-list", "--reverse", "--first-parent", "--no-merges", f"{BASE}..HEAD").split()
if git("rev-list", "--merges", f"{BASE}..HEAD").split():
    fails.append("merge commits in BASE..HEAD")
for i, sha in enumerate(commits):
    subject = git("log", "-1", "--format=%s", sha).strip()
    rows = raw("diff-tree", "--raw", "-r", "--no-renames", "--no-commit-id", sha)
    files = sorted(r[3] for r in rows)
    print(f"{sha[:12]} {subject} ({len(files)} files)")
    modes_ok(rows, f"{sha[:12]} ")
    directives(git("show", "--format=", "--no-renames", sha), f"{sha[:12]} ")
    if "CHANGELOG.md" in files and (why := changelog_ok(git("show", f"{sha}:CHANGELOG.md"), base_cl)):
        fails.append(f"{sha[:12]} {subject!r}: {why}")
    exp = expected[i] if i < len(expected) else None
    if exp is None:
        if files != ["CHANGELOG.md"]:
            fails.append(f"{sha[:12]} {subject!r}: extra commit after the changelog commit changes {files[:5]}")
        continue
    if subject != exp["subject"]:
        fails.append(f"{sha[:12]}: subject {subject!r}, expected {exp['subject']!r} (commit #{i + 1})")
        continue
    if exp.get("todo"):
        if files != [".rubocop_todo.yml"]:
            fails.append(f"{sha[:12]} {subject!r}: changes {files[:5]}, only .rubocop_todo.yml allowed")
        elif git("show", f"{sha}:.rubocop_todo.yml") != want_todo:
            fails.append(f"{sha[:12]}: .rubocop_todo.yml is not BASE without the R6c entries")
        continue
    if exp.get("changelog"):
        if files != ["CHANGELOG.md"]:
            fails.append(f"{sha[:12]} {subject!r}: changes {files[:5]}, only CHANGELOG.md allowed")
        continue
    if files != sorted(FILES):
        fails.append(f"{sha[:12]} {subject!r}: changes {files}, expected the {len(FILES)} R6c spec files")
    for f in FILES:
        r = subprocess.run(["git", "-C", str(ROOT), "cat-file", "-e", f"{sha}:{f}"], capture_output=True)
        if want[f] is None:
            if r.returncode == 0:
                fails.append(f"{sha[:12]} {subject!r}: {f} must be deleted")
        elif r.returncode != 0 or git("show", f"{sha}:{f}", binary=True) != want[f]:
            fails.append(f"{sha[:12]} {subject!r}: {f} is not BASE + {PATCH}")
if len(commits) < len(expected):
    fails.append(f"missing commits: {[c['subject'] for c in expected[len(commits):]]}")
for f in fails:
    print("FAIL:", f)
sys.exit(1 if fails else print("R6C COMMITS PASS"))
