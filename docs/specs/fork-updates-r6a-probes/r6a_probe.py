#!/usr/bin/env python3
"""Tree and commit probe for fork-updates-r6a (Lint/UselessAssignment in app/ and lib/).

Usage (from the repo root):
  python3 -I docs/specs/fork-updates-r6a-probes/r6a_probe.py tree <BASE_SHA>
  python3 -I docs/specs/fork-updates-r6a-probes/r6a_probe.py commits <BASE_SHA>

Everything comes from r6a_config.json next to this file: "files" (the 66 files), "keep" (stay in
the todo, with reasons), "steps" (the two autocorrect runs), "commits" (subjects in order).

Replay: the probe copies the Ruby files of "files" at a revision, BASE's .rubocop.yml, .ruby-version,
Gemfile, Gemfile.lock and the expected .rubocop_todo.yml into tmp/r6a-replay/<n>/ and runs, in the
bin/ci-local image with the gems of ${CHASKIQ_R6A_CACHE:-$HOME/.cache/chaskiq-r6a-ci},
`bundle exec rubocop --cache false -a --only <step cops> <files>` for the asked steps, in order.

tree - the working tree against BASE:
  1. "files" is exactly BASE's Exclude list of the cop in app/ and lib/ minus "keep" (spec defect
     otherwise); changed paths: exactly .rubocop_todo.yml, CHANGELOG.md and every file of "files",
     regular files with BASE's git mode; no untracked file; no ignored-but-present .rspec* or file
     under app/, lib/, config/, spec/;
  2. .rubocop_todo.yml is BASE with the lines of "files" removed from the cop's Exclude list, nothing
     else; .rubocop.yml unchanged; no `rubocop:` directive in an added line;
  3. no file of "files" uses binding, eval on a string, *_eval on a string, local_variables or ERB
     (a local the cop calls useless could be read there);
  4. every file of "files" in the tree is byte for byte the replay of both steps on BASE's version.
commits - BASE..HEAD (first parent, no merges) is exactly the "commits" list, in order:
  1. todo only, = the expected text;  2. exactly "files", each = replay of step 1 on its parent;
  3. only files of "files", each = replay of step 2 on its parent (and every file step 2 changes);
  4. CHANGELOG.md only, BASE with one block after "# Changelog" that mentions fork-updates-r6a;
  later commits: CHANGELOG.md only, same rule. No commit changes a git mode or adds/deletes a path.
Prints "R6A TREE PASS" / "R6A COMMITS PASS" or one "FAIL:" line per problem.
"""
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys

if len(sys.argv) != 3 or sys.argv[1] not in ("tree", "commits"):
    sys.exit("usage: r6a_probe.py tree|commits <BASE_SHA>")
MODE, BASE = sys.argv[1], sys.argv[2]
ROOT = pathlib.Path(subprocess.run(["git", "rev-parse", "--show-toplevel"], check=True,
                                   capture_output=True, text=True).stdout.strip())
HERE = pathlib.Path(__file__).resolve().parent
CFG = json.loads((HERE / "r6a_config.json").read_text(encoding="utf-8"))
COP, FILES, KEEP = CFG["cop"], CFG["files"], CFG["keep"]
HEADER = "# Changelog\n"
LEAKS = re.compile(r"\bbinding\b|(?<![.\w])eval\s*[(\"']|_eval\s*[(]?\s*[\"'<%]|\blocal_variables\b|\bERB\b|Erubi")
CACHE = pathlib.Path(os.environ.get("CHASKIQ_R6A_CACHE", str(pathlib.Path.home() / ".cache/chaskiq-r6a-ci")))
IMAGE = f"chaskiq-ci-local:ruby-{(ROOT / '.ruby-version').read_text().strip()}-ubuntu-26.04"
fails = []


def git(*a, binary=False):
    r = subprocess.run(["git", "-C", str(ROOT), *a], capture_output=True, text=not binary)
    if r.returncode != 0:
        err = r.stderr if not binary else r.stderr.decode()
        print(f"FAIL: git {' '.join(a)}: {err.strip()[:300]}")
        sys.exit(1)
    return r.stdout


def todo_list(text):
    out, cur = [], None
    for line in text.splitlines():
        m = re.match(r"^([A-Z][A-Za-z]+/[A-Za-z0-9]+):\s*$", line)
        if m:
            cur = m.group(1)
            continue
        m = re.match(r"^    - '([^']*)'\s*$", line)
        if m and cur == COP:
            out.append(m.group(1))
    return out


def expected_todo(text):
    head, *blocks = text.rstrip("\n").split("\n\n")
    out = []
    for b in blocks:
        if re.search(rf"(?m)^{re.escape(COP)}:$", b):
            b = "\n".join(ln for ln in b.split("\n")
                          if not (ln.startswith("    - '") and ln[7:].rstrip("'") in FILES))
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
    if "fork-updates-r6a" not in block:
        return "the added changelog block does not mention fork-updates-r6a"
    return None


def raw(*a):
    out = []
    for line in git(*a).splitlines():
        parts = line.split("\t", 1)
        meta = parts[0].split()
        if len(meta) >= 5 and len(parts) == 2:
            out.append((meta[0].lstrip(":"), meta[1], meta[4], parts[1]))
    return out


def modes_ok(rows, where):
    for old, new, status, p in rows:
        if status in ("A", "D", "T") or old != new or new not in ("100644", "100755"):
            fails.append(f"{where}{p}: mode {old} -> {new} (status {status}); only content edits allowed")


def directives(diff_text, where):
    for line in diff_text.splitlines():
        if line.startswith("+") and not line.startswith("+++") and re.search(r"rubocop\s*:", line, re.I):
            fails.append(f"{where}rubocop directive added: {line[:120]}")


SEQ = [0]


def replay(sources, steps):
    """sources: {path: bytes}; returns {path: bytes} after the autocorrect steps (indexes into CFG)."""
    SEQ[0] += 1
    d = ROOT / "tmp" / "r6a-replay" / str(SEQ[0])
    shutil.rmtree(d, ignore_errors=True)
    for f, data in sources.items():
        (d / f).parent.mkdir(parents=True, exist_ok=True)
        (d / f).write_bytes(data)
    for f in (".rubocop.yml", ".ruby-version", "Gemfile", "Gemfile.lock"):
        (d / f).write_bytes(git("show", f"{BASE}:{f}", binary=True))
    (d / ".rubocop_todo.yml").write_text(want_todo, encoding="utf-8")
    (d / "files.txt").write_text("".join(f"{f}\n" for f in sources))
    rel = d.relative_to(ROOT)
    script = "set -e; bundle install --quiet; mapfile -t f < files.txt\n" + "".join(
        f"bundle exec rubocop --cache false -a --only {','.join(CFG['steps'][i])} \"${{f[@]}}\" > step{i}.out 2>&1"
        f" || [ $? = 1 ]\n" for i in steps)
    r = subprocess.run(["docker", "run", "--rm", "--user", f"{os.getuid()}:{os.getgid()}", "-e", "HOME=/tmp",
                        "-e", "BUNDLE_PATH=/app/vendor/bundle", "-e", "BUNDLE_FROZEN=true",
                        "-e", "BUNDLE_GEMFILE=/app/Gemfile", "-v", f"{ROOT}:/app",
                        "-v", f"{CACHE}/bundle-ubuntu-26.04:/app/vendor/bundle", "-w", f"/app/{rel}", IMAGE,
                        "bash", "-c", script], capture_output=True, text=True)
    if r.returncode != 0:
        print(f"FAIL: replay exited {r.returncode}: {(r.stderr or r.stdout).strip()[-400:]}")
        sys.exit(1)
    for i in steps:
        out = (d / f"step{i}.out").read_text(errors="replace")
        if re.search(r"error occurred|An error|Traceback", out):
            print(f"FAIL: rubocop error in replay step {i + 1}: {out[-400:]}")
            sys.exit(1)
    return {f: (d / f).read_bytes() for f in sources}


if not CACHE.joinpath("bundle-ubuntu-26.04").is_dir():
    sys.exit(f"FAIL: gem cache {CACHE}/bundle-ubuntu-26.04 missing")
(ROOT / "tmp").mkdir(exist_ok=True)
shutil.rmtree(ROOT / "tmp" / "r6a-replay", ignore_errors=True)
base_todo = git("show", f"{BASE}:.rubocop_todo.yml")
base_cl = git("show", f"{BASE}:CHANGELOG.md")
want_todo = expected_todo(base_todo)
listed = [p for p in todo_list(base_todo) if re.match(r"^(app|lib)/", p)]
if sorted(set(listed) - set(KEEP)) != sorted(FILES) or not set(KEEP) <= set(listed):
    fails.append(f"r6a_config.json files/keep do not match BASE's {COP} list in app/ and lib/ (spec defect)")

if MODE == "tree":
    rows = raw("diff", "--raw", "--no-renames", BASE)
    modes_ok(rows, "")
    changed = {r[3] for r in rows}
    allowed = set(FILES) | {".rubocop_todo.yml", "CHANGELOG.md"}
    for p in sorted(changed - allowed):
        fails.append(f"{p}: changed, but not an R6a path")
    missing = sorted(allowed - changed)
    if missing:
        fails.append(f"R6a paths without the change: {missing[:10]}")
    untracked = [p for p in git("ls-files", "--others", "--exclude-standard").splitlines()
                 if p and p not in ("report.json", "report-blocked.md")]
    if untracked:
        fails.append(f"untracked files: {untracked[:10]}")
    for line in git("status", "--porcelain", "--ignored=matching", "--untracked-files=all").splitlines():
        p = line[3:]
        if line.startswith("!! ") and (re.match(r"^(\.rspec|(app|lib|config|spec)/)", p) or p.endswith(".rspec-local")):
            fails.append(f"{p}: ignored but present (affects the test run)")
    if (ROOT / ".rubocop_todo.yml").read_text(encoding="utf-8") != want_todo:
        fails.append(f".rubocop_todo.yml is not BASE with the {len(FILES)} files removed from {COP}")
    if (ROOT / ".rubocop.yml").read_text(encoding="utf-8") != git("show", f"{BASE}:.rubocop.yml"):
        fails.append(".rubocop.yml changed (R6a does not touch it)")
    directives(git("diff", "--no-renames", BASE), "")
    for f in FILES:
        for side, text in (("BASE", git("show", f"{BASE}:{f}")), ("tree", (ROOT / f).read_text(encoding="utf-8"))):
            for i, line in enumerate(text.splitlines(), 1):
                code = "" if line.lstrip().startswith("#") else line
                if LEAKS.search(code):
                    fails.append(f"{side} {f}:{i}: binding/eval/ERB - locals may be read dynamically: {line.strip()[:90]}")
    want = replay({f: git("show", f"{BASE}:{f}", binary=True) for f in FILES}, [0, 1])
    same = 0
    for f in FILES:
        if (ROOT / f).read_bytes() == want[f]:
            same += 1
        else:
            fails.append(f"{f}: not the replay of both autocorrect steps on BASE")
    print(f"files: {len(FILES)} (keep {len(KEEP)}), {same} equal to the replay")
    for f in fails:
        print("FAIL:", f)
    sys.exit(1 if fails else print("R6A TREE PASS"))

commits = git("rev-list", "--reverse", "--first-parent", "--no-merges", f"{BASE}..HEAD").split()
if git("rev-list", "--merges", f"{BASE}..HEAD").split():
    fails.append("merge commits in BASE..HEAD")
expected = CFG["commits"]
for i, sha in enumerate(commits):
    subject = git("log", "-1", "--format=%s", sha).strip()
    rows = raw("diff-tree", "--raw", "-r", "--no-renames", "--no-commit-id", sha)
    files = sorted(r[3] for r in rows)
    print(f"{sha[:12]} {subject} ({len(files)} files)")
    modes_ok(rows, f"{sha[:12]} ")
    directives(git("show", "--format=", "--no-renames", sha), f"{sha[:12]} ")
    if "CHANGELOG.md" in files and (why := changelog_ok(git("show", f"{sha}:CHANGELOG.md"), base_cl)):
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
    elif i in (1, 2):
        parent = {f: git("show", f"{sha}^:{f}", binary=True) for f in FILES}
        got = replay(parent, [i - 1])
        should = sorted(f for f in FILES if got[f] != parent[f])
        if files != should:
            fails.append(f"{sha[:12]} {subject!r}: changes {len(files)} files, replay of step {i} changes {len(should)}: "
                         f"extra {sorted(set(files) - set(should))[:5]}, missing {sorted(set(should) - set(files))[:5]}")
        for f in should:
            if f in files and git("show", f"{sha}:{f}", binary=True) != got[f]:
                fails.append(f"{sha[:12]} {subject!r}: {f} is not the replay of step {i} on the parent")
        if i == 1 and should != sorted(FILES):
            fails.append(f"{sha[:12]}: step 1 does not change every file of r6a_config.json (spec defect)")
    elif files != ["CHANGELOG.md"]:
        fails.append(f"{sha[:12]} {subject!r}: changes {files[:5]}, only CHANGELOG.md allowed")
if len(commits) < len(expected):
    fails.append(f"missing commits: {expected[len(commits):]}")
for f in fails:
    print("FAIL:", f)
sys.exit(1 if fails else print("R6A COMMITS PASS"))
