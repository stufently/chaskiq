#!/usr/bin/env python3
"""Semantic-equivalence and boundary probe for fork-updates-r1 (RuboCop backlog, step 1).

Usage (from the repo root): python3 -I docs/specs/fork-updates-r1-probes/r1_equiv_probe.py <BASE_SHA>

Checks the working tree against BASE:
  1. self-test: the bytecode comparator (r1_iseq.rb) calls a layout-only change SAME and a real
     change DIFF (removed assignment, different literal, different call, frozen_string_literal,
     string literal encoding, 0.0 -> -0.0), and a moved line in a line-sensitive file LINES, so a
     broken comparator cannot pass the milestone;
  2. every changed file is a Ruby source (*.rb, *.rake, *.ru, *.gemspec, *.jbuilder, Gemfile,
     Rakefile; not bin/, not templates such as .erb/.haml/.slim) and compiles to the same YARV
     bytecode as at BASE (line numbers, line events, node ids and code locations ignored, literals
     compared exactly; for line-sensitive files line numbers compared too), and `ruby -wc` prints
     no warning for it that BASE did not print; runs in the bin/ci-local image of .ruby-version;
  3. changed files are only .rubocop.yml, .rubocop_todo.yml, CHANGELOG.md and files that BASE's
     .rubocop_todo.yml lists under an R1 cop (outside docs/);
  4. .rubocop_todo.yml is byte-for-byte BASE's with the R1 sections and the docs/ entries removed
     (algorithm: expected_todo() below, the same text as section 5 of the spec);
  5. .rubocop.yml is byte-for-byte BASE's plus exactly DOCS_EXCLUDE after the vendor/** line of
     AllCops Exclude;
  6. no added line contains `<%` (RuboCop runs config files through ERB) in the two config files,
     nor `rubocop:disable`, `rubocop:todo` or `rubocop:enable` anywhere.
Prints one line per failure and "R1 EQUIV PASS" when everything holds.
"""
import pathlib
import re
import shutil
import subprocess
import sys

R1_COPS = [
    "Layout/EmptyLineAfterGuardClause",
    "Layout/EmptyLinesAfterModuleInclusion",
    "Layout/EmptyLinesAroundBlockBody",
    "Layout/EmptyLinesAroundClassBody",
    "Layout/EmptyLinesAroundMethodBody",
    "Layout/ExtraSpacing",
    "Layout/FirstArrayElementIndentation",
    "Layout/HashAlignment",
    "Layout/MultilineMethodCallIndentation",
    "Layout/SpaceAroundOperators",
    "Layout/SpaceBeforeBlockBraces",
    "Layout/SpaceInsideBlockBraces",
    "Style/RegexpLiteral",
    "Style/Semicolon",
    "Style/TrailingCommaInArguments",
    "Style/WordArray",
]
CONFIG_FILES = {".rubocop.yml", ".rubocop_todo.yml", "CHANGELOG.md"}
VENDOR_LINE = "    - 'vendor/**/*'\n"
DOCS_EXCLUDE = (
    "    # Frozen milestone specs and probes: their files are pinned by sha256 in the\n"
    "    # acceptance criteria of each spec, so they are never rewritten for style.\n"
    "    - 'docs/**/*'\n"
)
RUBY_SOURCE = re.compile(r"^(?!bin/)(.*\.(rb|rake|ru|gemspec|jbuilder)|(.*/)?(Gemfile|Rakefile))$")

if len(sys.argv) != 2:
    sys.exit("usage: r1_equiv_probe.py <BASE_SHA>")
BASE = sys.argv[1]
ROOT = pathlib.Path(subprocess.run(["git", "rev-parse", "--show-toplevel"], check=True,
                                   capture_output=True, text=True).stdout.strip())
HERE = pathlib.Path(__file__).resolve().parent
fails = []


def git(*args):
    return subprocess.run(["git", "-C", str(ROOT), *args], check=True, capture_output=True, text=True).stdout


def base_bytes(path):
    r = subprocess.run(["git", "-C", str(ROOT), "show", f"{BASE}:{path}"], capture_output=True)
    return r.stdout if r.returncode == 0 else None


def base_text(path):
    b = base_bytes(path)
    return None if b is None else b.decode("utf-8")


def expected_todo(text):
    """BASE .rubocop_todo.yml minus the R1 sections and the docs/ entries, as text.

    Blocks are separated by one blank line; the first block (header) stays. A block whose cop
    line is an R1 cop is dropped; in the other blocks every line starting with "    - 'docs/" is
    dropped; then a trailing "  Exclude:" line is dropped, and a block left with nothing after its
    cop line is dropped. Blocks are joined by one blank line, the file ends with one newline.
    """
    head, *blocks = text.rstrip("\n").split("\n\n")
    out = [head]
    for block in blocks:
        m = re.search(r"^([A-Z][A-Za-z]+/[A-Za-z0-9]+):$", block, re.M)
        if m and m.group(1) in R1_COPS:
            continue
        lines = [ln for ln in block.split("\n") if not ln.startswith("    - 'docs/")]
        if lines and lines[-1] == "  Exclude:":
            lines = lines[:-1]
        if m and lines and lines[-1] == m.group(1) + ":":
            continue
        out.append("\n".join(lines))
    return "\n\n".join(out) + "\n"


def first_text_diff(want, got):
    w, g = want.splitlines(), got.splitlines()
    for i in range(max(len(w), len(g))):
        a = w[i] if i < len(w) else "<EOF>"
        b = g[i] if i < len(g) else "<EOF>"
        if a != b:
            return f"line {i + 1}: expected {a!r:.100}, got {b!r:.100}"
    return "trailing newline differs"


def parse_todo(text):
    """{cop: {"Exclude": [paths], "<key>": "<value>"}} of a --auto-gen-config file."""
    out, cop, key = {}, None, None
    for line in text.splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        m = re.match(r"^([A-Z][A-Za-z]+/[A-Za-z0-9]+):\s*$", line)
        if m:
            cop, key = m.group(1), None
            out[cop] = {}
            continue
        m = re.match(r"^  ([A-Za-z]+):\s*(.*)$", line)
        if m and cop:
            key = m.group(1)
            out[cop][key] = [] if m.group(2) == "" else m.group(2)
            continue
        m = re.match(r"^    - '?([^']*)'?\s*$", line)
        if m and cop and isinstance(out[cop].get(key), list):
            out[cop][key].append(m.group(1))
            continue
        fails.append(f".rubocop_todo.yml: unparsed line {line!r}")
    return out


# 1 + 2. bytecode equivalence ------------------------------------------------------------------
ruby_version = (ROOT / ".ruby-version").read_text().strip()
image = f"chaskiq-ci-local:ruby-{ruby_version}-ubuntu-26.04"
if subprocess.run(["docker", "image", "inspect", image], capture_output=True).returncode != 0:
    print(f"FAIL: image {image} missing (built by bin/ci-local, e.g. bin/ci-local --only rubocop)")
    sys.exit(1)

changed = [p for p in git("diff", "--name-only", BASE).splitlines() if p]
untracked = [p for p in git("ls-files", "--others", "--exclude-standard").splitlines()
             if p and p not in ("report.json", "report-blocked.md")]
if untracked:
    fails.append(f"untracked files: {untracked[:10]}")
deleted = [p for p in git("diff", "--name-only", "--diff-filter=D", BASE).splitlines() if p]
if deleted:
    fails.append(f"deleted files: {deleted[:10]}")
ruby_files = [p for p in changed if p not in CONFIG_FILES and p not in deleted]
for p in ruby_files:
    if not RUBY_SOURCE.match(p):
        fails.append(f"{p}: not a Ruby source R1 may change (templates, bin/ and other files are out)")
ruby_files = [p for p in ruby_files if RUBY_SOURCE.match(p)]

work = ROOT / "tmp" / "r1-equiv"
shutil.rmtree(work, ignore_errors=True)
(work / "base").mkdir(parents=True)
(work / "selftest" / "base").mkdir(parents=True)
(work / "selftest" / "tree").mkdir(parents=True)
for p in ruby_files:
    t = base_bytes(p)
    if t is None:
        fails.append(f"{p}: new file (R1 only edits existing files)")
        continue
    dst = work / "base" / p
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_bytes(t)

SELFTEST = {
    # name: (base source, tree source, expected verdict)
    "layout.rb": ("class A\n  include B\n  def f(x)\n    if x\n      g( [1,2] )\n    end\n  end\nend\n",
                  "class A\n  include B\n\n  def f(x)\n    g([1, 2]) if x\n  end\nend\n", "SAME"),
    "assign.rb": ("def f\n  x = g\n  1\nend\n", "def f\n  g\n  1\nend\n", "DIFF"),
    "literal.rb": ("A = [\"a\", \"b\"]\n", "A = [\"a\", \"c\"]\n", "DIFF"),
    "call.rb": ("def f(a) = a.present? ? a : nil\n", "def f(a) = a.presence\n", "DIFF"),
    "frozen.rb": ("X = \"s\"\n", "# frozen_string_literal: true\n\nX = \"s\"\n", "DIFF"),
    "encoding.rb": ("# encoding: us-ascii\nX = \"a\"\n", "X = \"a\"\n", "DIFF"),
    "negzero.rb": ("X = 0.0\n", "X = -0.0\n", "DIFF"),
    "symenc.rb": ("# encoding: us-ascii\nX = :a\n", "X = :a\n", "SAME"),
    "lines.rb": ("def f\n  caller\nend\n", "\ndef f\n  caller\nend\n", "LINES"),
    "lines_ok.rb": ("def f\n  g\nend\n", "\ndef f\n  g\nend\n", "SAME"),
    "streval.rb": ("class_eval <<~RUBY\n  def x = 1\nRUBY\n", "\nclass_eval <<~RUBY\n  def x = 1\nRUBY\n", "LINES"),
}
for name, (b, t, _) in SELFTEST.items():
    (work / "selftest" / "base" / name).write_text(b)
    (work / "selftest" / "tree" / name).write_text(t)

uid = f"{subprocess.run(['id', '-u'], capture_output=True, text=True).stdout.strip()}:" \
      f"{subprocess.run(['id', '-g'], capture_output=True, text=True).stdout.strip()}"


def run_iseq(base_dir, tree_dir, paths):
    cmd = ["docker", "run", "--rm", "--user", uid, "-e", "HOME=/tmp", "-v", f"{ROOT}:/app:ro",
           "-v", f"{HERE / 'r1_iseq.rb'}:/r1_iseq.rb:ro", "-w", "/app", image,
           "ruby", "/r1_iseq.rb", base_dir, tree_dir, *paths]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        fails.append(f"r1_iseq.rb exited {r.returncode}: {r.stderr.strip()[:300]}")
    return r.stdout.splitlines()


st = {}
for line in run_iseq("/app/tmp/r1-equiv/selftest/base", "/app/tmp/r1-equiv/selftest/tree", sorted(SELFTEST)):
    verdict, name = line.split()[:2]
    if verdict in ("DIFF", "ERROR", "LINES") or name not in st:
        st[name] = verdict
for name, (_, _, want) in SELFTEST.items():
    if st.get(name) != want:
        fails.append(f"self-test {name}: comparator says {st.get(name)}, expected {want}")

if ruby_files:
    same = 0
    for line in run_iseq("/app/tmp/r1-equiv/base", "/app", ruby_files):
        if line.startswith("SAME "):
            same += 1
        else:
            fails.append(line)
    print(f"bytecode: {same}/{len(ruby_files)} changed Ruby files identical to BASE")

# 3. boundary ------------------------------------------------------------------------------------
base_todo_text = base_text(".rubocop_todo.yml") or ""
base_todo = parse_todo(base_todo_text)
missing_cops = [c for c in R1_COPS if c not in base_todo]
if missing_cops:
    fails.append(f"R1 cops absent from BASE .rubocop_todo.yml: {missing_cops}")
allowed = {p for c in R1_COPS for p in base_todo.get(c, {}).get("Exclude", []) if not p.startswith("docs/")}
for p in changed:
    if p not in CONFIG_FILES and p not in allowed:
        fails.append(f"{p}: changed, but BASE .rubocop_todo.yml lists it under no R1 cop")

# 4. .rubocop_todo.yml (text) -------------------------------------------------------------------
tree_todo_path = ROOT / ".rubocop_todo.yml"
tree_todo_text = tree_todo_path.read_text(encoding="utf-8") if tree_todo_path.exists() else ""
want_todo = expected_todo(base_todo_text)
if tree_todo_text != want_todo:
    fails.append(f".rubocop_todo.yml differs from BASE minus R1 sections and docs/ lines: "
                 f"{first_text_diff(want_todo, tree_todo_text)}")

# 5. .rubocop.yml (text) -------------------------------------------------------------------------
b_cfg = base_text(".rubocop.yml") or ""
t_cfg = (ROOT / ".rubocop.yml").read_text(encoding="utf-8")
allcops = re.search(r"^AllCops:\n(?:[ #].*\n|\n)*", b_cfg, re.M)
if not allcops or allcops.group(0).count(VENDOR_LINE) != 1:
    fails.append(".rubocop.yml at BASE: no single \"    - 'vendor/**/*'\" line in AllCops (spec defect)")
else:
    at = allcops.start() + allcops.group(0).index(VENDOR_LINE) + len(VENDOR_LINE)
    want_cfg = b_cfg[:at] + DOCS_EXCLUDE + b_cfg[at:]
    if t_cfg != want_cfg:
        fails.append(f".rubocop.yml is not BASE plus exactly the docs/** exclude: {first_text_diff(want_cfg, t_cfg)}")

# 6. no ERB in configs, no inline directives -----------------------------------------------------
for line in git("diff", "-U0", BASE, "--", ".rubocop.yml", ".rubocop_todo.yml").splitlines():
    if line.startswith("+") and not line.startswith("+++") and "<%" in line:
        fails.append(f"ERB tag added to a RuboCop config: {line[:160]}")
for line in git("diff", "-U0", BASE).splitlines():
    if line.startswith("+") and not line.startswith("+++") and re.search(r"rubocop:(disable|todo|enable)", line):
        fails.append(f"inline rubocop directive added: {line[:160]}")

for f in fails:
    print("FAIL:", f)
if fails:
    sys.exit(1)
print("R1 EQUIV PASS")
