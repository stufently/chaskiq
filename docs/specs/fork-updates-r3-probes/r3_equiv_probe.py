#!/usr/bin/env python3
"""Equivalence and boundary probe for fork-updates-r3 (`# frozen_string_literal: true`).

Usage (from the repo root): python3 -I docs/specs/fork-updates-r3-probes/r3_equiv_probe.py <BASE_SHA>

R3 adds the magic comment to the files BASE's .rubocop_todo.yml lists under
Style/FrozenStringLiteralComment and lets Style/RedundantFreeze drop the `.freeze` it makes
redundant. Checks the working tree against BASE:
  1. self-test: r3_frozen.rb `shape` accepts the comment alone and refuses look-alikes (a changed
     literal, a comment below the first token, a changed line elsewhere); `freeze` explains only
     `<frozen literal>.freeze`; `mutate` finds every planted mutation of a literal (mutator method,
     memo of each_with_object, StringIO buffer, read buffer, parameter mutated in another file,
     a method returning a literal mutated by its caller, array element, constant) and none in
     `+""`, `"".dup`, `String.new`, interpolated strings;
  2. every changed path is a regular file with BASE's git mode, and is .rubocop_todo.yml,
     CHANGELOG.md, or a file of FSL_FILES (= the BASE todo list of the cop minus NOT_INSPECTED);
  3. per file of FSL_FILES: the text is BASE plus the comment and a blank line at the top (for
     FREEZE_FILES, additionally lines where exactly one `.freeze` was removed); r3_frozen.rb `shape`
     says SAME (FREEZE_FILES: `freeze` on base+comment -> tree says SAME or EXPLAINED); every file
     of FSL_FILES is changed (none left without the comment);
  4. r3_frozen.rb `mutate` over the tree: no literal of an FSL_FILES file can reach a mutation
     (findings must be empty; REVIEWED would list a reviewed exception with its reason - empty);
  2b. no ignored-but-present file that affects the test run: .rspec* at the root or under any
     directory, anything under app/, lib/, config/, spec/;
  5. .rubocop_todo.yml is byte-for-byte BASE minus the Style/FrozenStringLiteralComment block;
     .rubocop.yml is unchanged.
Prints one line per failure and "R3 EQUIV PASS" when everything holds.
"""
import pathlib
import re
import shutil
import subprocess
import sys

COP = "Style/FrozenStringLiteralComment"
# Cops with 0 offenses in the tree (r3_backlog_probe.sh, r3_commits_probe.py, in commit order):
# the todo cop and its knock-on (the comment makes `"literal".freeze` redundant).
R3_COPS = ["Style/FrozenStringLiteralComment", "Style/RedundantFreeze"]
TODO_ADDITIONS = {}  # no new todo entries in R3
# Listed in the BASE todo, but RuboCop never inspects it (not in --list-target-files: no .rb
# extension, bin/ is not in AllCops Include); left untouched.
NOT_INSPECTED = ["bin/setup"]
# Files where the magic comment makes a `.freeze` redundant (Style/RedundantFreeze, measured at BASE).
FREEZE_FILES = ["app/services/digital_ocean/api.rb", "app/services/message_apis/twilio_phone/store.rb"]
REVIEWED = {}  # "path:line kind" -> reason; findings of `mutate` reviewed by the spec author (none)
CONFIG_FILES = {".rubocop_todo.yml", "CHANGELOG.md"}
MAGIC = "# frozen_string_literal: true\n"

if len(sys.argv) != 2:
    sys.exit("usage: r3_equiv_probe.py <BASE_SHA>")
BASE = sys.argv[1]
ROOT = pathlib.Path(subprocess.run(["git", "rev-parse", "--show-toplevel"], check=True,
                                   capture_output=True, text=True).stdout.strip())
HERE = pathlib.Path(__file__).resolve().parent
fails = []


def git(*args):
    r = subprocess.run(["git", "-C", str(ROOT), *args], capture_output=True, text=True)
    if r.returncode != 0:
        print(f"FAIL: git {' '.join(args)}: {r.stderr.strip()[:300]}")
        sys.exit(1)
    return r.stdout


def base_bytes(path):
    r = subprocess.run(["git", "-C", str(ROOT), "show", f"{BASE}:{path}"], capture_output=True)
    return r.stdout if r.returncode == 0 else None


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
    """BASE todo minus the block whose cop line is COP (blocks are separated by one blank line)."""
    head, *blocks = text.rstrip("\n").split("\n\n")
    keep = [b for b in blocks if not re.search(rf"^{re.escape(COP)}:$", b, re.M)]
    return "\n\n".join([head] + keep) + "\n"


def with_magic(text):
    """Where RuboCop puts the comment: after a shebang line and encoding comments."""
    lines = text.splitlines(keepends=True)
    i = 0
    if lines and lines[0].startswith("#!"):
        i = 1
    while i < len(lines) and re.match(r"^#.*\b(en)?coding\s*[:=]", lines[i], re.I):
        i += 1
    return "".join(lines[:i] + [MAGIC, "\n"] + lines[i:])


def text_ok(path, base, tree):
    want = with_magic(base)
    if tree == want:
        return None
    if path not in FREEZE_FILES:
        return "text is not BASE + magic comment and blank line at the top"
    w, t = want.splitlines(keepends=True), tree.splitlines(keepends=True)
    if len(w) != len(t):
        return "line count differs from BASE + magic comment"
    for i, (a, b) in enumerate(zip(w, t)):
        if a != b and (a.count(".freeze") < 1 or a.replace(".freeze", "", 1) != b):
            return f"line {i + 1}: only one `.freeze` may be removed: {a.strip()[:80]!r} -> {b.strip()[:80]!r}"
    return None


ruby_version = (ROOT / ".ruby-version").read_text().strip()
image = f"chaskiq-ci-local:ruby-{ruby_version}-ubuntu-26.04"
if subprocess.run(["docker", "image", "inspect", image], capture_output=True).returncode != 0:
    print(f"FAIL: image {image} missing (built by bin/ci-local, e.g. bin/ci-local --only rubocop)")
    sys.exit(1)
uid = f"{subprocess.run(['id', '-u'], capture_output=True, text=True).stdout.strip()}:" \
      f"{subprocess.run(['id', '-g'], capture_output=True, text=True).stdout.strip()}"


def frozen(*args):
    cmd = ["docker", "run", "--rm", "--user", uid, "-e", "HOME=/tmp", "-v", f"{ROOT}:/app:ro",
           "-v", f"{HERE / 'r3_frozen.rb'}:/r3_frozen.rb:ro", "-w", "/app", image, "ruby", "/r3_frozen.rb", *args]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        fails.append(f"r3_frozen.rb {args[0]} exited {r.returncode}: {r.stderr.strip()[:300]}")
    return r.stdout.splitlines()


base_todo_text = (base_bytes(".rubocop_todo.yml") or b"").decode("utf-8")
listed = todo_list(base_todo_text, COP)
if not listed:
    fails.append(f"{COP} absent from BASE .rubocop_todo.yml (spec defect)")
FSL_FILES = [p for p in listed if p not in NOT_INSPECTED]

# 2. changed paths ---------------------------------------------------------------------------------
changed = [p for p in git("diff", "--name-only", "--no-renames", BASE).splitlines() if p]
untracked = [p for p in git("ls-files", "--others", "--exclude-standard").splitlines()
             if p and p not in ("report.json", "report-blocked.md")]
if untracked:
    fails.append(f"untracked files: {untracked[:10]}")
for line in git("diff", "--raw", "--no-renames", BASE).splitlines():
    m = re.match(r"^:(\d{6}) (\d{6}) \S+ \S+ (\S)\t(.+)$", line)
    if not m:
        continue
    old_mode, new_mode, status, path = m.groups()
    if status in ("A", "D") or old_mode != new_mode or new_mode not in ("100644", "100755"):
        fails.append(f"{path}: git mode {old_mode} -> {new_mode} (status {status}); only content edits of "
                     f"regular files are allowed")
for p in changed:
    fp = ROOT / p
    if fp.is_symlink() or (fp.exists() and not fp.is_file()):
        fails.append(f"{p}: not a regular file in the tree")
    if p not in CONFIG_FILES and p not in FSL_FILES:
        fails.append(f"{p}: changed, but not a file of the BASE todo list of {COP}")
# Ignored but present files that change what the test run loads: an .rspec-local (could hold
# --dry-run), Ruby or config under app/, lib/, config/, spec/ (autoloaded / required by spec_helper).
for line in git("status", "--porcelain", "--ignored=matching", "--untracked-files=all").splitlines():
    if line.startswith("!! "):
        p = line[3:]
        if re.match(r"^(\.rspec|(app|lib|config|spec)/)", p) or p.endswith(".rspec-local"):
            fails.append(f"{p}: ignored but present (affects the test run)")
left = [p for p in FSL_FILES if p not in changed]
if left:
    fails.append(f"files of the {COP} list without the change: {left[:10]}")

# 1. self-test -------------------------------------------------------------------------------------
work = ROOT / "tmp" / "r3-equiv"
shutil.rmtree(work, ignore_errors=True)
for d in ("st/base", "st/tree", "mt", "base", "fz"):
    (work / d).mkdir(parents=True)
SHAPE = [  # (name, base, tree, mode, expected)
    ("ok.rb", 'x = "a"\n', MAGIC + '\nx = "a"\n', "shape", "SAME"),
    ("bang.rb", '#!/usr/bin/env ruby\n# encoding: utf-8\nx = "a"\n',
     '#!/usr/bin/env ruby\n# encoding: utf-8\n' + MAGIC + '\nx = "a"\n', "shape", "SAME"),
    ("lit.rb", 'x = "a"\n', MAGIC + '\nx = "b"\n', "shape", "DIFF"),
    ("late.rb", 'x = "a"\n', 'x = "a"\n' + MAGIC, "shape", "DIFF"),
    ("had.rb", MAGIC + 'x = "a"\n', MAGIC + "\n" + MAGIC + 'x = "a"\n', "shape", "DIFF"),
    ("call.rb", 'x = "a"\n', MAGIC + '\nx = "a"\ny\n', "shape", "DIFF"),
    ("fz.rb", MAGIC + '\nX = "a".freeze\n', MAGIC + '\nX = "a"\n', "freeze", "EXPLAINED"),
    ("fz_ary.rb", MAGIC + '\nX = [1].freeze\n', MAGIC + '\nX = [1]\n', "freeze", "DIFF"),
    ("fz_int.rb", MAGIC + '\nX = "#{a}".freeze\n', MAGIC + '\nX = "#{a}"\n', "freeze", "DIFF"),
]
for mode in ("shape", "freeze"):
    rows = [r for r in SHAPE if r[3] == mode]
    for name, b, t, _, _ in rows:
        (work / "st/base" / name).write_text(b)
        (work / "st/tree" / name).write_text(t)
    (work / f"st/{mode}.list").write_text("".join(f"{r[0]}\n" for r in rows))
    got = {ln.split()[1]: ln.split()[0] for ln in frozen(mode, "/app/tmp/r3-equiv/st/base",
                                                          "/app/tmp/r3-equiv/st/tree", f"/app/tmp/r3-equiv/st/{mode}.list")
           if len(ln.split()) > 1}
    for name, _, _, _, want in rows:
        if got.get(name) != want:
            fails.append(f"self-test {mode} {name}: checker says {got.get(name)!r}, expected {want!r}")
MT_A = MAGIC + '''
class A
  SEP = "-"
  def f(x = "")
    s = "a"
    s << "b"
    x << "c"
    @buf ||= ""
    @buf.concat("d")
    y = c ? "p" : String.new
    y.gsub!("p", "q")
    z = "ok".dup
    z << "fine"
    v = +""
    v << "fine"
    u = String.new("")
    u << "fine"
    SEP << "x"
    StringIO.new("")
    StringIO.new(+"")
    w = ["a", "b"]
    w.first.strip!
    helper("lit")
    sock.read(10, "")
    "x#{1}y" << "z"
    %w[a].each_with_object("") { |e, m| m << e }
    name.force_encoding("BINARY")
  end

  def name
    "n"
  end
end
'''
MT_B = 'def helper(str)\n  str << "!"\nend\n\ndef other(o)\n  o.name << "x"\nend\n'
(work / "mt/a.rb").write_text(MT_A)
(work / "mt/b.rb").write_text(MT_B)
(work / "mt/list").write_text("a.rb\n")
(work / "mt/all").write_text("a.rb\nb.rb\n")
want_lines = {("a.rb", 7, "mutator"), ("a.rb", 8, "mutator"), ("a.rb", 10, "mutator"), ("a.rb", 12, "mutator"),
              ("a.rb", 19, "mutator"), ("a.rb", 20, "buffer"), ("a.rb", 23, "mutator"), ("a.rb", 24, "param"),
              ("a.rb", 25, "buffer"), ("a.rb", 27, "mutator"), ("a.rb", 28, "mutator"), ("a.rb", 28, "return"),
              ("b.rb", 6, "return")}
got_lines = set()
for ln in frozen("mutate", "/app/tmp/r3-equiv/mt", "/app/tmp/r3-equiv/mt/list", "/app/tmp/r3-equiv/mt/all"):
    m = re.match(r"^FIND (\S+):(\d+) (\S+)", ln)
    if m:
        got_lines.add((m.group(1), int(m.group(2)), m.group(3)))
if got_lines != want_lines:
    fails.append(f"self-test mutate: missed {sorted(want_lines - got_lines)}, extra {sorted(got_lines - want_lines)}")

# 3. per-file shape --------------------------------------------------------------------------------
shape_files, freeze_files = [], []
for p in FSL_FILES:
    if p not in changed:
        continue
    b = base_bytes(p)
    if b is None:
        fails.append(f"{p}: absent at BASE")
        continue
    base, tree = b.decode("utf-8"), (ROOT / p).read_text(encoding="utf-8")
    why = text_ok(p, base, tree)
    if why:
        fails.append(f"{p}: {why}")
        continue
    dst = work / "base" / p
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_text(base)
    if p in FREEZE_FILES and tree != with_magic(base):
        fz = work / "fz" / p
        fz.parent.mkdir(parents=True, exist_ok=True)
        fz.write_text(with_magic(base))
        freeze_files.append(p)
    else:
        shape_files.append(p)
(work / "shape.list").write_text("".join(f"{p}\n" for p in shape_files))
(work / "freeze.list").write_text("".join(f"{p}\n" for p in freeze_files))
counts = {}
if shape_files:
    for ln in frozen("shape", "/app/tmp/r3-equiv/base", "/app", "/app/tmp/r3-equiv/shape.list"):
        counts[ln.split()[0]] = counts.get(ln.split()[0], 0) + 1
        if not ln.startswith("SAME "):
            fails.append(ln)
if freeze_files:
    for ln in frozen("freeze", "/app/tmp/r3-equiv/fz", "/app", "/app/tmp/r3-equiv/freeze.list"):
        counts[ln.split()[0]] = counts.get(ln.split()[0], 0) + 1
        if not ln.startswith(("SAME ", "EXPLAINED ")):
            fails.append(ln)
print(f"files: {len(FSL_FILES)} in the {COP} list, {len(shape_files)} comment only, "
      f"{len(freeze_files)} comment + RedundantFreeze; verdicts {counts}")

# 4. literal mutations -----------------------------------------------------------------------------
all_ruby = [p for p in git("ls-files", "--", "app", "lib", "config", "spec").splitlines()
            if re.search(r"\.(rb|rake)$", p)]
(work / "all.list").write_text("".join(f"{p}\n" for p in all_ruby))
(work / "fsl.list").write_text("".join(f"{p}\n" for p in FSL_FILES))
out = frozen("mutate", "/app", "/app/tmp/r3-equiv/fsl.list", "/app/tmp/r3-equiv/all.list")
if not out or not out[-1].startswith("MUTATE "):
    fails.append(f"r3_frozen.rb mutate gave no summary: {out[-3:]}")
for ln in out:
    m = re.match(r"^FIND (\S+:\d+ \S+)", ln)
    if m and m.group(1) not in REVIEWED:
        fails.append(f"literal may be mutated: {ln[5:200]}")
print(out[-1] if out else "MUTATE ?")

# 5. config files ----------------------------------------------------------------------------------
tree_todo = (ROOT / ".rubocop_todo.yml").read_text(encoding="utf-8")
if tree_todo != expected_todo(base_todo_text):
    fails.append(f".rubocop_todo.yml is not BASE minus the {COP} block")
if (ROOT / ".rubocop.yml").read_bytes() != (base_bytes(".rubocop.yml") or b""):
    fails.append(".rubocop.yml changed (R3 does not touch it)")

for f in fails:
    print("FAIL:", f)
if fails:
    sys.exit(1)
print("R3 EQUIV PASS")
