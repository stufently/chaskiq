#!/usr/bin/env python3
"""Config probe for fork-updates-r7a (owner decisions: three cops disabled with a written reason).

Usage (from the repo root):
  python3 -I docs/specs/fork-updates-r7a-probes/r7a_probe.py tree <BASE_SHA>
  python3 -I docs/specs/fork-updates-r7a-probes/r7a_probe.py commits <BASE_SHA>

tree: checks the working tree against BASE:
  1. self-test of expected_config()/expected_todo() on small samples (a broken helper cannot pass);
  2. the only changed paths are .rubocop.yml, .rubocop_todo.yml, CHANGELOG.md; each keeps BASE's git
     mode; no untracked file; no ignored-but-present .rspec* or file under app/, lib/, config/, spec/;
  3. .rubocop.yml is byte for byte expected_config(BASE): BLOCK inserted right before the only
     "AllCops:" line, nothing else changed;
  4. .rubocop_todo.yml is byte for byte expected_todo(BASE): the blocks of R7A_COPS removed, nothing
     else;
  5. RuboCop's resolved config (image of bin/ci-local, `rubocop --show-cops`) has `Enabled: false`
     for each of R7A_COPS;
  6. CHANGELOG.md is BASE with one non-empty block inserted right after "# Changelog" that mentions
     fork-updates-r7a (BASE text below byte for byte).
commits: BASE..HEAD (first parent, no merges) is exactly
  1. "Disable three cops by owner decision" - changes exactly .rubocop.yml and .rubocop_todo.yml,
     both equal to the expected text at that commit (the two must land together: CI is strict);
  2. "Note fork-updates-r7a in changelog" - changes only CHANGELOG.md (rule 6 at that commit);
  3. after it, only commits changing CHANGELOG.md alone (rule 6 at each);
  every commit keeps the git mode of every path it touches (no type change, no add/delete).
Prints one line per failure and "R7A TREE PASS" / "R7A COMMITS PASS".
"""
import pathlib
import re
import subprocess
import sys

R7A_COPS = ["Style/Documentation", "Naming/AccessorMethodName", "Naming/MethodParameterName"]
BLOCK = """# Owner decision 2026-11-20 (docs/specs/fork-updates-rubocop-plan.md, R7): stub class comments
# ("# Class for X") carry no information; classes are documented where it matters (GraphQL schema,
# README, specs).
Style/Documentation:
  Enabled: false
# Owner decision 2026-11-20 (same plan, R7): get_x/set_x names are part of public interfaces
# (GraphQL resolvers, plugin and integration APIs); renaming them breaks plugins and integrations.
Naming/AccessorMethodName:
  Enabled: false
# Owner decision 2026-11-20 (same plan, R7): parameter names of public methods are kept as they are
# (short names mirror external APIs); renaming them breaks plugins and integrations.
Naming/MethodParameterName:
  Enabled: false
"""
ANCHOR = "AllCops:\n"
CHANGED_OK = {".rubocop.yml", ".rubocop_todo.yml", "CHANGELOG.md"}
HEADER = "# Changelog\n"
COMMIT_SUBJECTS = ["Disable three cops by owner decision", "Note fork-updates-r7a in changelog"]

if len(sys.argv) != 3 or sys.argv[1] not in ("tree", "commits"):
    sys.exit("usage: r7a_probe.py tree|commits <BASE_SHA>")
MODE, BASE = sys.argv[1], sys.argv[2]
ROOT = pathlib.Path(subprocess.run(["git", "rev-parse", "--show-toplevel"], check=True,
                                   capture_output=True, text=True).stdout.strip())
fails = []


def git(*args):
    r = subprocess.run(["git", "-C", str(ROOT), *args], capture_output=True, text=True)
    if r.returncode != 0:
        print(f"FAIL: git {' '.join(args)}: {r.stderr.strip()[:300]}")
        sys.exit(1)
    return r.stdout


def expected_config(text):
    """BLOCK inserted right before the single line "AllCops:" (at the start of a line)."""
    hits = [m.start() for m in re.finditer(r"(?m)^AllCops:\n", text)]
    if len(hits) != 1:
        raise ValueError(f"{len(hits)} 'AllCops:' lines in .rubocop.yml (spec defect)")
    return text[:hits[0]] + BLOCK + text[hits[0]:]


def expected_todo(text):
    """Blocks (separated by one blank line) whose cop line is one of R7A_COPS removed."""
    head, *blocks = text.rstrip("\n").split("\n\n")
    keep = [b for b in blocks if not any(re.search(rf"(?m)^{re.escape(c)}:$", b) for c in R7A_COPS)]
    return "\n\n".join([head] + keep) + "\n"


def changelog_ok(cur, base):
    rest = base[len(HEADER):]
    if not base.startswith(HEADER):
        return "BASE CHANGELOG.md does not start with '# Changelog' (spec defect)"
    if not cur.startswith(HEADER) or not cur.endswith(rest) or len(cur) < len(base):
        return "CHANGELOG.md is not BASE with a block inserted after '# Changelog' (BASE text changed)"
    block = cur[len(HEADER):len(cur) - len(rest)]
    if not block.strip():
        return "no changelog entry added"
    if "fork-updates-r7a" not in block:
        return "the added changelog block does not mention fork-updates-r7a"
    return None


# 1. self-test ---------------------------------------------------------------------------------------
cfg = "a: 1\n\nAllCops:\n  X: 1\n"
if expected_config(cfg) != "a: 1\n\n" + BLOCK + "AllCops:\n  X: 1\n":
    fails.append("self-test expected_config")
todo = "# head\n\n# c\nStyle/Documentation:\n  Exclude:\n    - 'a.rb'\n\nStyle/X:\n  Exclude:\n    - 'b.rb'\n\n" \
       "Naming/MethodParameterName:\n  Enabled: false\n"
if expected_todo(todo) != "# head\n\nStyle/X:\n  Exclude:\n    - 'b.rb'\n":
    fails.append("self-test expected_todo")
if changelog_ok(HEADER + "\n## x fork-updates-r7a\n" + "\nold\n", HEADER + "\nold\n") is not None or \
   changelog_ok(HEADER + "\nold\n", HEADER + "\nold\n") is None or \
   changelog_ok(HEADER + "\n## fork-updates-r7a\n" + "\nOLD\n", HEADER + "\nold\n") is None:
    fails.append("self-test changelog_ok")

base_cfg = git("show", f"{BASE}:.rubocop.yml")
base_todo = git("show", f"{BASE}:.rubocop_todo.yml")
base_cl = git("show", f"{BASE}:CHANGELOG.md")
missing = [c for c in R7A_COPS if not re.search(rf"(?m)^{re.escape(c)}:$", base_todo)]
if missing:
    fails.append(f"cops without a todo section at BASE: {missing} (spec defect)")
if any(re.search(rf"(?m)^{re.escape(c)}:", base_cfg) for c in R7A_COPS):
    fails.append("BASE .rubocop.yml already configures one of the cops (spec defect)")
want_cfg, want_todo = expected_config(base_cfg), expected_todo(base_todo)


def mode_check(raw, where):
    for line in raw.splitlines():
        parts = line.split("\t", 1)
        meta = parts[0].split()
        if len(meta) < 5 or len(parts) < 2:
            continue
        old_mode, new_mode, status = meta[0].lstrip(":"), meta[1], meta[4]
        if status in ("A", "D", "T") or old_mode != new_mode or new_mode not in ("100644", "100755"):
            fails.append(f"{where}: {parts[1]}: mode {old_mode} -> {new_mode} (status {status}); only content edits")


if MODE == "tree":
    changed = [p for p in git("diff", "--name-only", "--no-renames", BASE).splitlines() if p]
    for p in changed:
        if p not in CHANGED_OK:
            fails.append(f"{p}: changed (R7a changes only {sorted(CHANGED_OK)})")
    mode_check(git("diff", "--raw", "--no-renames", BASE), "tree")
    untracked = [p for p in git("ls-files", "--others", "--exclude-standard").splitlines()
                 if p and p not in ("report.json", "report-blocked.md")]
    if untracked:
        fails.append(f"untracked files: {untracked[:10]}")
    for line in git("status", "--porcelain", "--ignored=matching", "--untracked-files=all").splitlines():
        p = line[3:]
        if line.startswith("!! ") and (re.match(r"^(\.rspec|(app|lib|config|spec)/)", p) or p.endswith(".rspec-local")):
            fails.append(f"{p}: ignored but present (affects RuboCop/tests)")
    if (ROOT / ".rubocop.yml").read_text(encoding="utf-8") != want_cfg:
        fails.append(".rubocop.yml is not BASE with BLOCK inserted before 'AllCops:'")
    if (ROOT / ".rubocop_todo.yml").read_text(encoding="utf-8") != want_todo:
        fails.append(".rubocop_todo.yml is not BASE minus the blocks of the three cops")
    why = changelog_ok((ROOT / "CHANGELOG.md").read_text(encoding="utf-8"), base_cl)
    if why:
        fails.append(why)
    image = f"chaskiq-ci-local:ruby-{(ROOT / '.ruby-version').read_text().strip()}-ubuntu-26.04"
    import os
    cache = pathlib.Path(os.environ.get("CHASKIQ_R7A_CACHE", pathlib.Path.home() / ".cache" / "chaskiq-r7a-ci")) / "bundle-ubuntu-26.04"
    uid = f"{subprocess.run(['id', '-u'], capture_output=True, text=True).stdout.strip()}:" \
          f"{subprocess.run(['id', '-g'], capture_output=True, text=True).stdout.strip()}"
    r = subprocess.run(["docker", "run", "--rm", "--user", uid, "-e", "HOME=/tmp", "-e", "BUNDLE_PATH=/bundle",
                        "-e", "BUNDLE_FROZEN=true", "-v", f"{ROOT}:/app:ro", "-v", f"{cache}:/bundle:ro",
                        "-w", "/app", image, "bundle", "exec", "rubocop", "--show-cops", ",".join(R7A_COPS)],
                       capture_output=True, text=True)
    if r.returncode != 0:
        fails.append(f"rubocop --show-cops exited {r.returncode}: {r.stderr.strip()[:300]}")
    else:
        for c in R7A_COPS:
            m = re.search(rf"(?ms)^{re.escape(c)}:\n(.*?)(?=^\S|\Z)", r.stdout)
            if not m or not re.search(r"(?m)^  Enabled: false$", m.group(1)):
                fails.append(f"{c}: resolved config is not 'Enabled: false'")
    print(f"changed: {changed}")
else:
    commits = git("rev-list", "--reverse", "--first-parent", "--no-merges", f"{BASE}..HEAD").split()
    if git("rev-list", "--merges", f"{BASE}..HEAD").split():
        fails.append("merge commits in BASE..HEAD")
    for i, sha in enumerate(commits):
        subject = git("log", "-1", "--format=%s", sha).strip()
        files = sorted(f for f in git("diff-tree", "--no-commit-id", "--name-only", "-r", "--no-renames", sha).split() if f)
        print(f"{sha[:12]} {subject} ({len(files)} files)")
        mode_check(git("diff-tree", "--raw", "-r", "--no-renames", "--no-commit-id", sha), f"{sha[:12]} {subject!r}")
        want = COMMIT_SUBJECTS[i] if i < len(COMMIT_SUBJECTS) else None
        if want and subject != want:
            fails.append(f"{sha[:12]}: subject {subject!r}, expected {want!r} (commit #{i + 1})")
            continue
        if i == 0:
            if files != [".rubocop.yml", ".rubocop_todo.yml"]:
                fails.append(f"{sha[:12]} {subject!r}: changes {files}, expected exactly .rubocop.yml and .rubocop_todo.yml")
            if git("show", f"{sha}:.rubocop.yml") != want_cfg:
                fails.append(f"{sha[:12]}: .rubocop.yml is not the expected text")
            if git("show", f"{sha}:.rubocop_todo.yml") != want_todo:
                fails.append(f"{sha[:12]}: .rubocop_todo.yml is not the expected text")
        else:
            if files != ["CHANGELOG.md"]:
                fails.append(f"{sha[:12]} {subject!r}: changes {files[:5]}, only CHANGELOG.md allowed")
            why = changelog_ok(git("show", f"{sha}:CHANGELOG.md"), base_cl)
            if why:
                fails.append(f"{sha[:12]} {subject!r}: {why}")
    if len(commits) < len(COMMIT_SUBJECTS):
        fails.append(f"missing commits: {COMMIT_SUBJECTS[len(commits):]}")

for f in fails:
    print("FAIL:", f)
if fails:
    sys.exit(1)
print(f"R7A {MODE.upper()} PASS")
