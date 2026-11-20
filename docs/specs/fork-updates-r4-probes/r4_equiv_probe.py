#!/usr/bin/env python3
"""Equivalence and boundary probe for fork-updates-r4 (Style/ClassAndModuleChildren, nested style).

Usage (from the repo root): python3 -I docs/specs/fork-updates-r4-probes/r4_equiv_probe.py <BASE_SHA>

Checks the working tree against BASE:
  1. self-test: r4_nest.rb `shape` accepts compact -> nested (also two levels, with superclass and
     re-indented body) and refuses look-alikes: a changed literal, an extra statement in the new
     module, a `<<-` heredoc whose content got re-indented, a dropped superclass, an added
     `# rubocop:disable` comment, a changed comment;
  2. every changed path is a regular file with BASE's git mode, and is .rubocop_todo.yml,
     CHANGELOG.md or a file of R4_FILES (= BASE todo list of the cop minus KEEP); every file of
     R4_FILES is changed; no untracked file; no ignored-but-present .rspec* or file under app/,
     lib/, config/, spec/;
  3. r4_nest.rb `shape` says SAME for every changed Ruby file (BASE vs tree);
  4. .rubocop_todo.yml is byte for byte BASE with the cop's Exclude list cut down to KEEP;
     .rubocop.yml unchanged;
  5. no changed file uses Module.nesting, const_missing, class variables, __LINE__, caller, eval on
     a string, binding, ERB/Erubi or *_eval on a string (lexical scope or line numbers would leak,
     or constants are referenced from strings r4_nest.rb refs cannot see).
Prints one line per failure and "R4 EQUIV PASS".
"""
import os
import pathlib
import re
import shutil
import subprocess
import sys

COP = "Style/ClassAndModuleChildren"
R4_COPS = ["Style/ClassAndModuleChildren"]
# Stay compact (kept in the todo):
# - twilio_phone/api.rb: nesting changes what a constant resolves to - measured by resolve_gate_r4.sh
#   on the draft: `Twilio` (the twilio-ruby gem) would become MessageApis::Twilio;
# - the four presenters evaluate ERB templates with `template.result(binding)`: constants inside the
#   template strings resolve in the lexical scope of the method and are invisible to r4_nest.rb refs.
KEEP = [
    "app/services/message_apis/article_search/presenter.rb",
    "app/services/message_apis/calendly/presenter.rb",
    "app/services/message_apis/twilio_phone/api.rb",
    "app/services/message_apis/twilio_phone/presenter.rb",
    "app/services/message_apis/ui_catalog/presenter.rb",
]
TODO_ADDITIONS = {}  # no new todo entries (read by r4_backlog_probe.sh)
# The only offense growth r4_backlog_probe.sh accepts: cop -> file -> (BASE count, tree count), exact.
# Longer lines after one more indent level; both files stay excluded from Layout/LineLength (R8).
ALLOWED_GROWTH = {
    "Layout/LineLength": {
        "app/controllers/api/v1/hooks_controller.rb": (2, 3),
        "app/services/message_apis/slack/api.rb": (4, 5),
    },
}
CHANGED_OK = {".rubocop_todo.yml", "CHANGELOG.md"}
LEAKS = re.compile(r"Module\.nesting|const_missing|@@[a-z_]|__LINE__|\bcaller(_locations)?\b|(?<![.\w])eval\s*\("
                   r"|\bbinding\b|\bERB\b|Erubi|_eval\s*[(]?\s*[\"'<%]")

if len(sys.argv) != 2:
    sys.exit("usage: r4_equiv_probe.py <BASE_SHA>")
BASE = sys.argv[1]
ROOT = pathlib.Path(subprocess.run(["git", "rev-parse", "--show-toplevel"], check=True,
                                   capture_output=True, text=True).stdout.strip())
HERE = pathlib.Path(__file__).resolve().parent
fails = []


def git(*a):
    r = subprocess.run(["git", "-C", str(ROOT), *a], capture_output=True, text=True)
    if r.returncode != 0:
        print(f"FAIL: git {' '.join(a)}: {r.stderr.strip()[:300]}")
        sys.exit(1)
    return r.stdout


def todo_list(text, cop):
    out, cur = [], None
    for line in text.splitlines():
        m = re.match(r"^([A-Z][A-Za-z]+/[A-Za-z0-9]+):\s*$", line)
        if m:
            cur = m.group(1)
            continue
        m = re.match(r"^    - '([^']*)'\s*$", line)
        if m and cur == cop:
            out.append(m.group(1))
    return out


def expected_todo(text):
    """BASE todo; in the block of COP only the Exclude lines of KEEP stay."""
    head, *blocks = text.rstrip("\n").split("\n\n")
    out = []
    for b in blocks:
        if re.search(rf"(?m)^{re.escape(COP)}:$", b):
            b = "\n".join(ln for ln in b.split("\n")
                          if not ln.startswith("    - '") or ln[7:].rstrip("'") in KEEP)
        out.append(b)
    return "\n\n".join([head] + out) + "\n"


image = f"chaskiq-ci-local:ruby-{(ROOT / '.ruby-version').read_text().strip()}-ubuntu-26.04"
uid = f"{os.getuid()}:{os.getgid()}"


def nest(*args):
    r = subprocess.run(["docker", "run", "--rm", "--user", uid, "-e", "HOME=/tmp", "-v", f"{ROOT}:/app:ro",
                        "-v", f"{HERE / 'r4_nest.rb'}:/r4_nest.rb:ro", "-w", "/app", image, "ruby", "/r4_nest.rb", *args],
                       capture_output=True, text=True)
    if r.returncode != 0:
        fails.append(f"r4_nest.rb {args[0]} exited {r.returncode}: {r.stderr.strip()[:300]}")
    return r.stdout.splitlines()


base_todo = git("show", f"{BASE}:.rubocop_todo.yml")
listed = todo_list(base_todo, COP)
if not listed or any(k not in listed for k in KEEP):
    fails.append(f"{COP} section missing at BASE or KEEP not in it (spec defect)")
R4_FILES = [p for p in listed if p not in KEEP]

# 1. self-test -------------------------------------------------------------------------------------
work = ROOT / "tmp" / "r4-equiv"
shutil.rmtree(work, ignore_errors=True)
for d in ("st/base", "st/tree", "base"):
    (work / d).mkdir(parents=True)
CASES = [
    ("ok.rb", "class A::B < C\n  X = 1\n  def f = \"s\"\nend\n",
     "module A\n  class B < C\n    X = 1\n    def f = \"s\"\n  end\nend\n", "SAME"),
    ("two.rb", "class A::B::C\n  include D\nend\n", "module A\n  module B\n    class C\n      include D\n    end\n  end\nend\n", "SAME"),
    ("mod.rb", "module A::B\n  def self.x = 1\nend\n", "module A\n  module B\n    def self.x = 1\n  end\nend\n", "SAME"),
    ("lit.rb", "class A::B\n  X = 1\nend\n", "module A\n  class B\n    X = 2\n  end\nend\n", "DIFF"),
    ("extra.rb", "class A::B\nend\n", "module A\n  Y = 1\n  class B\n  end\nend\n", "DIFF"),
    ("heredoc.rb", "class A::B\n  X = <<-T\n  a\n  T\nend\n", "module A\n  class B\n    X = <<-T\n    a\n    T\n  end\nend\n", "DIFF"),
    ("super.rb", "class A::B < C\nend\n", "module A\n  class B\n  end\nend\n", "DIFF"),
    ("directive.rb", "class A::B\n  X = 1\nend\n",
     "module A\n  class B # rubocop:disable Style/ClassAndModuleChildren\n    X = 1\n  end\nend\n", "DIFF"),
    ("comment.rb", "# a\nclass A::B\n  # b\nend\n", "# a\nmodule A\n  class B\n    # c\n  end\nend\n", "DIFF"),
    ("commentok.rb", "# a\nclass A::B\n  # b\n  X = 1 # c\nend\n",
     "# a\nmodule A\n  class B\n    # b\n    X = 1 # c\n  end\nend\n", "SAME"),
]
for name, b, t, _ in CASES:
    (work / "st/base" / name).write_text(b)
    (work / "st/tree" / name).write_text(t)
(work / "st/list").write_text("".join(f"{c[0]}\n" for c in CASES))
got = {ln.split()[1]: ln.split()[0] for ln in nest("shape", "/app/tmp/r4-equiv/st/base", "/app/tmp/r4-equiv/st/tree",
                                                   "/app/tmp/r4-equiv/st/list") if len(ln.split()) > 1}
for name, _, _, want in CASES:
    if got.get(name) != want:
        fails.append(f"self-test {name}: checker says {got.get(name)!r}, expected {want!r}")

# 2. changed paths ---------------------------------------------------------------------------------
changed = [p for p in git("diff", "--name-only", "--no-renames", BASE).splitlines() if p]
for line in git("diff", "--raw", "--no-renames", BASE).splitlines():
    parts = line.split("\t", 1)
    meta = parts[0].split()
    if len(meta) >= 5 and len(parts) == 2:
        old, new, status = meta[0].lstrip(":"), meta[1], meta[4]
        if status in ("A", "D", "T") or old != new or new not in ("100644", "100755"):
            fails.append(f"{parts[1]}: mode {old} -> {new} (status {status}); only content edits of regular files")
for p in changed:
    if p not in CHANGED_OK and p not in R4_FILES:
        fails.append(f"{p}: changed, but not a file of the {COP} list (minus KEEP)")
    fp = ROOT / p
    if fp.is_symlink() or (fp.exists() and not fp.is_file()):
        fails.append(f"{p}: not a regular file")
left = [p for p in R4_FILES if p not in changed]
if left:
    fails.append(f"files of the {COP} list without the change: {left[:10]}")
untracked = [p for p in git("ls-files", "--others", "--exclude-standard").splitlines()
             if p and p not in ("report.json", "report-blocked.md")]
if untracked:
    fails.append(f"untracked files: {untracked[:10]}")
for line in git("status", "--porcelain", "--ignored=matching", "--untracked-files=all").splitlines():
    p = line[3:]
    if line.startswith("!! ") and (re.match(r"^(\.rspec|(app|lib|config|spec)/)", p) or p.endswith(".rspec-local")):
        fails.append(f"{p}: ignored but present (affects the test run)")

# 3. shape -----------------------------------------------------------------------------------------
ruby = [p for p in changed if p in R4_FILES]
for p in ruby:
    dst = work / "base" / p
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_text(git("show", f"{BASE}:{p}"))
(work / "list").write_text("".join(f"{p}\n" for p in ruby))
same = 0
if ruby:
    for ln in nest("shape", "/app/tmp/r4-equiv/base", "/app", "/app/tmp/r4-equiv/list"):
        if ln.startswith("SAME "):
            same += 1
        else:
            fails.append(ln)
print(f"files: {len(R4_FILES)} in the {COP} list minus KEEP {KEEP}, {len(ruby)} changed, {same} SAME")

# 4. config ------------------------------------------------------------------------------------------
if (ROOT / ".rubocop_todo.yml").read_text(encoding="utf-8") != expected_todo(base_todo):
    fails.append(f".rubocop_todo.yml is not BASE with the {COP} list cut down to KEEP")
if (ROOT / ".rubocop.yml").read_text(encoding="utf-8") != git("show", f"{BASE}:.rubocop.yml"):
    fails.append(".rubocop.yml changed (R4 does not touch it)")

# 5. lexical-scope / line leaks ----------------------------------------------------------------------
for p in ruby:
    for i, line in enumerate((ROOT / p).read_text(encoding="utf-8").splitlines(), 1):
        code = line.split("#", 1)[0] if not line.lstrip().startswith("#") else ""
        if LEAKS.search(code):
            fails.append(f"{p}:{i}: uses lexical scope or line numbers: {line.strip()[:100]}")

for f in fails:
    print("FAIL:", f)
if fails:
    sys.exit(1)
print("R4 EQUIV PASS")
