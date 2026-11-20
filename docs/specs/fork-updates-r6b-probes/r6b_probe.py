#!/usr/bin/env python3
"""Tree and commit probe for fork-updates-r6b (Lint/UnusedMethodArgument in app/ and lib/).

Usage (from the repo root):
  python3 -I docs/specs/fork-updates-r6b-probes/r6b_probe.py tree <BASE_SHA>
  python3 -I docs/specs/fork-updates-r6b-probes/r6b_probe.py commits <BASE_SHA>

Everything comes from r6b_config.json next to this file: "files" (the 28 files the autocorrect
changes), "keep" (stay in the todo, with reasons), "todo_only" (todo lines that go without a code
change: keyword-only offenses, now allowed), "rubocop_yml_anchor"/"rubocop_yml_insert" (the owner's
setting), "step" (the cop autocorrected), "commits" (subjects in order).

Expected .rubocop.yml = BASE with "rubocop_yml_insert" right after "rubocop_yml_anchor". Expected
.rubocop_todo.yml = BASE with the cop's Exclude list cut down to "keep".
Replay: the Ruby files of "files" at a revision, the expected .rubocop.yml and .rubocop_todo.yml and
BASE's .ruby-version, Gemfile, Gemfile.lock are copied to tmp/r6b-replay/<n>/; in the bin/ci-local
image with the gems of ${CHASKIQ_R6B_CACHE:-$HOME/.cache/chaskiq-r6b-ci}:
`bundle exec rubocop --cache false -a --only <step> <files>`.
Guard: r6b_guard.rb (Prism) on BASE's and the tree's (or parent's and commit's) versions of "files".

tree - the working tree against BASE:
  1. files + keep + todo_only == BASE's Exclude list of the cop (spec defect otherwise), no spec/
     file in "files"; changed paths: exactly .rubocop.yml, .rubocop_todo.yml, CHANGELOG.md and every
     file of "files", regular files with BASE's git mode; no untracked file; no ignored-but-present
     .rspec* or file under app/, lib/, config/, spec/;
  2. .rubocop.yml and .rubocop_todo.yml are the expected texts; no `rubocop:` directive added;
  3. every file of "files" equals the replay on BASE's version, byte for byte;
  4. the guard passes on BASE -> tree.
commits - BASE..HEAD (first parent, no merges) is exactly "commits", in order:
  1. .rubocop.yml only (= expected);  2. .rubocop_todo.yml only (= expected);
  3. exactly "files", each = replay on its parent, guard passes parent -> commit;
  4. CHANGELOG.md only, BASE with one block after "# Changelog" that mentions fork-updates-r6b;
  later commits: CHANGELOG.md only, same rule. No commit changes a git mode or adds/deletes a path.
Prints "R6B TREE PASS" / "R6B COMMITS PASS" or one "FAIL:" line per problem.
"""
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys

if len(sys.argv) != 3 or sys.argv[1] not in ("tree", "commits"):
    sys.exit("usage: r6b_probe.py tree|commits <BASE_SHA>")
MODE, BASE = sys.argv[1], sys.argv[2]
ROOT = pathlib.Path(subprocess.run(["git", "rev-parse", "--show-toplevel"], check=True,
                                   capture_output=True, text=True).stdout.strip())
HERE = pathlib.Path(__file__).resolve().parent
CFG = json.loads((HERE / "r6b_config.json").read_text(encoding="utf-8"))
COP, FILES, KEEP, TODO_ONLY = CFG["cop"], CFG["files"], CFG["keep"], CFG["todo_only"]
HEADER = "# Changelog\n"
CACHE = pathlib.Path(os.environ.get("CHASKIQ_R6B_CACHE", str(pathlib.Path.home() / ".cache/chaskiq-r6b-ci")))
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
                          if not (ln.startswith("    - '") and ln[7:].rstrip("'") not in KEEP))
        out.append(b)
    return "\n\n".join([head] + out) + "\n"


def expected_yml(text):
    anchor = CFG["rubocop_yml_anchor"]
    if text.count(anchor) != 1:
        print("FAIL: BASE .rubocop.yml does not contain the anchor exactly once (spec defect)")
        sys.exit(1)
    return text.replace(anchor, anchor + CFG["rubocop_yml_insert"])


def changelog_ok(cur, base_cl):
    rest = base_cl[len(HEADER):]
    if not base_cl.startswith(HEADER):
        return "BASE CHANGELOG.md does not start with '# Changelog' (spec defect)"
    if not cur.startswith(HEADER) or not cur.endswith(rest) or len(cur) < len(base_cl):
        return "CHANGELOG.md is not BASE with a block inserted after '# Changelog' (BASE text changed)"
    block = cur[len(HEADER):len(cur) - len(rest)]
    if not block.strip():
        return "no changelog entry added"
    if "fork-updates-r6b" not in block:
        return "the added changelog block does not mention fork-updates-r6b"
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


def workdir(sources):
    SEQ[0] += 1
    d = ROOT / "tmp" / "r6b-replay" / str(SEQ[0])
    shutil.rmtree(d, ignore_errors=True)
    for f, data in sources.items():
        (d / f).parent.mkdir(parents=True, exist_ok=True)
        (d / f).write_bytes(data)
    return d


def docker(d, script):
    rel = d.relative_to(ROOT)
    # Create the bind-mount target as our user: if Docker creates it, it is root-owned in the clone.
    (ROOT / "vendor" / "bundle").mkdir(parents=True, exist_ok=True)
    return subprocess.run(["docker", "run", "--rm", "--user", f"{os.getuid()}:{os.getgid()}", "-e", "HOME=/tmp",
                           "-e", "BUNDLE_PATH=/app/vendor/bundle", "-e", "BUNDLE_FROZEN=true",
                           "-e", "BUNDLE_GEMFILE=/app/Gemfile", "-v", f"{ROOT}:/app",
                           "-v", f"{CACHE}/bundle-ubuntu-26.04:/app/vendor/bundle", "-w", f"/app/{rel}", IMAGE,
                           "bash", "-c", script], capture_output=True, text=True)


def replay(sources):
    d = workdir(sources)
    for f in (".ruby-version", "Gemfile", "Gemfile.lock"):
        (d / f).write_bytes(git("show", f"{BASE}:{f}", binary=True))
    (d / ".rubocop.yml").write_text(want_yml, encoding="utf-8")
    (d / ".rubocop_todo.yml").write_text(want_todo, encoding="utf-8")
    (d / "files.txt").write_text("".join(f"{f}\n" for f in sources))
    r = docker(d, "set -e; bundle install --quiet; mapfile -t f < files.txt\n"
                  f"bundle exec rubocop --cache false -a --only {CFG['step']} \"${{f[@]}}\" > step.out 2>&1 || [ $? = 1 ]")
    if r.returncode != 0:
        print(f"FAIL: replay exited {r.returncode}: {(r.stderr or r.stdout).strip()[-400:]}")
        sys.exit(1)
    out = (d / "step.out").read_text(errors="replace")
    if re.search(r"error occurred|An error|Traceback", out):
        print(f"FAIL: rubocop error in replay: {out[-400:]}")
        sys.exit(1)
    return {f: (d / f).read_bytes() for f in sources}


def guard(before, after, where):
    d = workdir({})
    for side, src in (("base", before), ("tree", after)):
        for f, data in src.items():
            (d / side / f).parent.mkdir(parents=True, exist_ok=True)
            (d / side / f).write_bytes(data)
    (d / "list").write_text("".join(f"{f}\n" for f in after))
    shutil.copy(HERE / "r6b_guard.rb", d / "r6b_guard.rb")
    r = docker(d, "ruby r6b_guard.rb base tree list")
    for line in r.stdout.splitlines():
        if line.startswith("BAD"):
            fails.append(f"{where}guard: {line[4:]}")
    if r.returncode != 0 and not any(l.startswith("BAD") for l in r.stdout.splitlines()):
        fails.append(f"{where}guard exited {r.returncode}: {(r.stderr or r.stdout).strip()[-300:]}")
    m = re.search(r"^R6B GUARD PASS .*$", r.stdout, re.M)
    return m.group(0) if m else None


if not CACHE.joinpath("bundle-ubuntu-26.04").is_dir():
    sys.exit(f"FAIL: gem cache {CACHE}/bundle-ubuntu-26.04 missing")
(ROOT / "tmp").mkdir(exist_ok=True)
shutil.rmtree(ROOT / "tmp" / "r6b-replay", ignore_errors=True)
base_todo = git("show", f"{BASE}:.rubocop_todo.yml")
base_cl = git("show", f"{BASE}:CHANGELOG.md")
want_todo = expected_todo(base_todo)
want_yml = expected_yml(git("show", f"{BASE}:.rubocop.yml"))
if sorted(todo_list(base_todo)) != sorted(set(FILES) | set(KEEP) | set(TODO_ONLY)) or \
        len(set(FILES) | set(KEEP) | set(TODO_ONLY)) != len(FILES) + len(KEEP) + len(TODO_ONLY) or \
        any(f.startswith("spec/") for f in FILES):
    fails.append(f"r6b_config.json files/keep/todo_only do not match BASE's {COP} list (spec defect)")

if MODE == "tree":
    rows = raw("diff", "--raw", "--no-renames", BASE)
    modes_ok(rows, "")
    changed = {r[3] for r in rows}
    allowed = set(FILES) | {".rubocop.yml", ".rubocop_todo.yml", "CHANGELOG.md"}
    for p in sorted(changed - allowed):
        fails.append(f"{p}: changed, but not an R6b path")
    missing = sorted(allowed - changed)
    if missing:
        fails.append(f"R6b paths without the change: {missing[:10]}")
    untracked = [p for p in git("ls-files", "--others", "--exclude-standard").splitlines()
                 if p and p not in ("report.json", "report-blocked.md")]
    if untracked:
        fails.append(f"untracked files: {untracked[:10]}")
    for line in git("status", "--porcelain", "--ignored=matching", "--untracked-files=all").splitlines():
        p = line[3:]
        if line.startswith("!! ") and (re.match(r"^(\.rspec|(app|lib|config|spec)/)", p) or p.endswith(".rspec-local")):
            fails.append(f"{p}: ignored but present (affects the test run)")
    if (ROOT / ".rubocop.yml").read_text(encoding="utf-8") != want_yml:
        fails.append(".rubocop.yml is not BASE with the owner's Lint/UnusedMethodArgument block")
    if (ROOT / ".rubocop_todo.yml").read_text(encoding="utf-8") != want_todo:
        fails.append(f".rubocop_todo.yml is not BASE with the {COP} list cut down to keep")
    directives(git("diff", "--no-renames", BASE), "")
    base_src = {f: git("show", f"{BASE}:{f}", binary=True) for f in FILES}
    want = replay(base_src)
    same = sum(1 for f in FILES if (ROOT / f).read_bytes() == want[f])
    for f in FILES:
        if (ROOT / f).read_bytes() != want[f]:
            fails.append(f"{f}: not the replay of the autocorrect on BASE")
    verdict = guard(base_src, {f: (ROOT / f).read_bytes() for f in FILES}, "")
    print(f"files: {len(FILES)} (keep {len(KEEP)}, todo only {len(TODO_ONLY)}), {same} equal to the replay; {verdict}")
    for f in fails:
        print("FAIL:", f)
    sys.exit(1 if fails else print("R6B TREE PASS"))

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
        if files != [".rubocop.yml"]:
            fails.append(f"{sha[:12]} {subject!r}: changes {files[:5]}, only .rubocop.yml allowed")
        elif git("show", f"{sha}:.rubocop.yml") != want_yml:
            fails.append(f"{sha[:12]}: .rubocop.yml is not the expected text")
    elif i == 1:
        if files != [".rubocop_todo.yml"]:
            fails.append(f"{sha[:12]} {subject!r}: changes {files[:5]}, only .rubocop_todo.yml allowed")
        elif git("show", f"{sha}:.rubocop_todo.yml") != want_todo:
            fails.append(f"{sha[:12]}: .rubocop_todo.yml is not the expected text")
    elif i == 2:
        if files != sorted(FILES):
            fails.append(f"{sha[:12]} {subject!r}: changes {len(files)} files, expected the {len(FILES)} of r6b_config.json: "
                         f"extra {sorted(set(files) - set(FILES))[:5]}, missing {sorted(set(FILES) - set(files))[:5]}")
        parent = {f: git("show", f"{sha}^:{f}", binary=True) for f in FILES}
        got = replay(parent)
        for f in FILES:
            if git("show", f"{sha}:{f}", binary=True) != got[f]:
                fails.append(f"{sha[:12]} {subject!r}: {f} is not the replay of the autocorrect on the parent")
        guard(parent, {f: git("show", f"{sha}:{f}", binary=True) for f in FILES}, f"{sha[:12]} ")
    elif files != ["CHANGELOG.md"]:
        fails.append(f"{sha[:12]} {subject!r}: changes {files[:5]}, only CHANGELOG.md allowed")
if len(commits) < len(expected):
    fails.append(f"missing commits: {expected[len(commits):]}")
for f in fails:
    print("FAIL:", f)
sys.exit(1 if fails else print("R6B COMMITS PASS"))
