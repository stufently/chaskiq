#!/usr/bin/env python3
"""Per-cop equivalence and boundary probe for fork-updates-r2 (RuboCop backlog, step 2).

Usage (from the repo root): python3 -I docs/specs/fork-updates-r2-probes/r2_equiv_probe.py <BASE_SHA>

R2 autocorrects cops whose rewrite DOES change the bytecode. Every difference must be explained
by the rewrite of a cop that is allowed for that file. Checks the working tree against BASE:
  1. self-test: r2_canon.rb explains each cop's own transformation (SAME/EXPLAINED with exactly
     that cop) and refuses look-alikes that are not equivalent (guard not at the method tail,
     `return` inside a block, parentheses under defined?, **splat in the array hash, super with a
     reassigned parameter, non-empty string in the interpolation, `unless x.present?` turned into
     `if x.blank?`, a forwarded parameter read in a default value, a changed literal next to an
     allowed rewrite), so a broken checker cannot pass the milestone;
  2. every changed path is a regular file with BASE's git mode (no symlink, no submodule, no mode
     change) and a Ruby source (*.rb, *.rake, *.ru, *.gemspec, *.jbuilder, Gemfile,
     Rakefile; not bin/, not templates) that BASE's .rubocop_todo.yml lists under an R2 cop;
  3. per file, the allowed cops are the R2 cops whose BASE todo section lists it plus the declared
     cascades (CASCADES); r2_canon.rb must say SAME or EXPLAINED (each named cop needed), never
     DIFF/ERROR/LINES, and `ruby -wc` must print no new warning; prints a per-cop table;
  4. app/, lib/, config/ do not reopen NilClass (condition of the EmptyStringInsideInterpolation
     rewrite: nil.to_s == ""); gems under vendor/bundle are out of reach of this check;
  5. .rubocop_todo.yml is byte-for-byte expected_todo(BASE): R2 sections removed, the declared
     TODO_ADDITIONS inserted in sorted position (a section absent at BASE is created from
     NEW_SECTION_HEADERS in cop-name order); .rubocop.yml is unchanged;
  6. comment changes: `rubocop:` directives may change only in files listed under
     Style/DirectiveScope, and only as removed `# rubocop:disable X` / `# rubocop:enable X` plus
     added `# rubocop:disable-next X` for an X that was disabled there at BASE; no `<%` added to
     the config files.
Prints one line per failure and "R2 EQUIV PASS" when everything holds.
"""
import pathlib
import re
import shutil
import subprocess
import sys

R2_COPS = [
    "Style/IfUnlessModifier",
    "Style/GuardClause",
    "Style/RedundantParentheses",
    "Style/RedundantReturn",
    "Style/HashAsLastArrayItem",
    "Naming/BlockForwarding",
    "Style/ArgumentsForwarding",
    "Style/SuperArguments",
    "Style/EmptyStringInsideInterpolation",
    "Style/DirectiveScope",
]
# A cop's rewrite creates offenses of another cop in the same file (measured on BASE): the second
# cop's rewrite is allowed wherever the first one is.
CASCADES = {
    "Style/IfUnlessModifier": ["Style/GuardClause"],  # long modifier -> block if at the method tail
}
# New offenses the rewrites create that R2 must not fix (they belong to later milestones):
# added to the existing todo sections, nothing else.
TODO_ADDITIONS = {
    "Metrics/BlockLength": ["app/models/app.rb"],  # IfUnlessModifier expands a modifier inside a block
    # GuardClause writes `return unless x.present?`; turning it into `return if x.blank?` is equal
    # only when blank? == !present? for the receiver's type: that check is R3, not R2.
    "Rails/Blank": [
        "app/channels/application_cable/connection.rb",
        "app/graphql/types/app_type.rb",
        "app/jobs/email_chat_notifier_job.rb",
        "app/services/action_trigger.rb",
    ],
    "Style/ReturnNilInPredicateMethodDefinition": ["app/services/message_apis/open_ai/api.rb"],  # GuardClause in a ? method
}
# Header comments of a todo section that does not exist at BASE (as --auto-gen-config writes them).
NEW_SECTION_HEADERS = {
    "Rails/Blank": [
        "# This cop supports unsafe autocorrection (--autocorrect-all).",
        "# Configuration parameters: NilOrEmpty, NotPresent, UnlessPresent.",
    ],
}
NILCLASS_PATCH = re.compile(r"\bclass\s+NilClass\b|\bNilClass\s*\.\s*(class_eval|class_exec|module_eval|prepend|include|"
                            r"define_method|send|public_send)\b|\brefine\s*\(?\s*NilClass\b|"
                            r"\b(prepend|include)\s*\(?\s*NilClass\b")
CONFIG_FILES = {".rubocop.yml", ".rubocop_todo.yml", "CHANGELOG.md"}
RUBY_SOURCE = re.compile(r"^(?!bin/)(.*\.(rb|rake|ru|gemspec|jbuilder)|(.*/)?(Gemfile|Rakefile))$")
DIRECTIVE = re.compile(r"^\s*# rubocop:(disable|enable|disable-next|todo)\s+(.+?)\s*$")

if len(sys.argv) != 2:
    sys.exit("usage: r2_equiv_probe.py <BASE_SHA>")
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


def todo_sections(text):
    """{cop: [Exclude paths]} of BASE .rubocop_todo.yml."""
    out, cop = {}, None
    for line in text.splitlines():
        m = re.match(r"^([A-Z][A-Za-z]+/[A-Za-z0-9]+):\s*$", line)
        if m:
            cop = m.group(1)
            out[cop] = []
            continue
        m = re.match(r"^    - '([^']*)'\s*$", line)
        if m and cop:
            out[cop].append(m.group(1))
    return out


def expected_todo(text):
    """BASE .rubocop_todo.yml minus the R2 sections, plus TODO_ADDITIONS, as text.

    Blocks are separated by one blank line; the first block (header) stays. A block whose cop
    line is an R2 cop is dropped. For a cop in TODO_ADDITIONS each path is added as
    "    - '<path>'" to its Exclude list, and the list is kept in sorted order (Python str order,
    the order --auto-gen-config wrote). A cop in TODO_ADDITIONS without a section at BASE gets a
    new block: NEW_SECTION_HEADERS lines, "<Cop>:", "  Exclude:", the sorted paths; it is placed
    before the first block whose cop name sorts after it (the BASE blocks are in cop-name order).
    Blocks are joined by one blank line, one final newline.
    """
    head, *blocks = text.rstrip("\n").split("\n\n")
    out = []
    present = set()
    for block in blocks:
        m = re.search(r"^([A-Z][A-Za-z]+/[A-Za-z0-9]+):$", block, re.M)
        if m:
            present.add(m.group(1))
        if m and m.group(1) in R2_COPS:
            continue
        if m and m.group(1) in TODO_ADDITIONS:
            lines = block.split("\n")
            ex = [ln for ln in lines if ln.startswith("    - '")]
            rest = [ln for ln in lines if not ln.startswith("    - '")]
            new = sorted(set(ex) | {f"    - '{p}'" for p in TODO_ADDITIONS[m.group(1)]})
            block = "\n".join(rest + new)
        out.append((m.group(1) if m else "", block))
    for cop, paths in TODO_ADDITIONS.items():
        if cop in present:
            continue
        block = "\n".join(NEW_SECTION_HEADERS[cop] + [f"{cop}:", "  Exclude:"] +
                          sorted(f"    - '{p}'" for p in paths))
        at = next((i for i, (c, _) in enumerate(out) if c > cop), len(out))
        out.insert(at, (cop, block))
    return "\n\n".join([head] + [b for _, b in out]) + "\n"


def first_text_diff(want, got):
    w, g = want.splitlines(), got.splitlines()
    for i in range(max(len(w), len(g))):
        a = w[i] if i < len(w) else "<EOF>"
        b = g[i] if i < len(g) else "<EOF>"
        if a != b:
            return f"line {i + 1}: expected {a!r:.100}, got {b!r:.100}"
    return "trailing newline differs"


ruby_version = (ROOT / ".ruby-version").read_text().strip()
image = f"chaskiq-ci-local:ruby-{ruby_version}-ubuntu-26.04"
if subprocess.run(["docker", "image", "inspect", image], capture_output=True).returncode != 0:
    print(f"FAIL: image {image} missing (built by bin/ci-local, e.g. bin/ci-local --only rubocop)")
    sys.exit(1)

base_todo_text = base_text(".rubocop_todo.yml") or ""
base_todo = todo_sections(base_todo_text)
missing = [c for c in R2_COPS if c not in base_todo]
if missing:
    fails.append(f"R2 cops absent from BASE .rubocop_todo.yml: {missing} (spec defect)")
for cop, paths in TODO_ADDITIONS.items():
    if cop not in base_todo and cop not in NEW_SECTION_HEADERS:
        fails.append(f"TODO_ADDITIONS: section {cop} absent at BASE and no NEW_SECTION_HEADERS (spec defect)")
    elif cop in base_todo and sorted(base_todo[cop]) != base_todo[cop]:
        fails.append(f"TODO_ADDITIONS: BASE section {cop} is not sorted (spec defect)")


def allowed_cops(path):
    cops = [c for c in R2_COPS if path in base_todo.get(c, [])]
    i = 0
    while i < len(cops):
        for extra in CASCADES.get(cops[i], []):
            if extra not in cops:
                cops.append(extra)
        i += 1
    return cops


# 2. changed files ---------------------------------------------------------------------------------
changed = [p for p in git("diff", "--name-only", BASE).splitlines() if p]
untracked = [p for p in git("ls-files", "--others", "--exclude-standard").splitlines()
             if p and p not in ("report.json", "report-blocked.md")]
if untracked:
    fails.append(f"untracked files: {untracked[:10]}")
deleted = [p for p in git("diff", "--name-only", "--diff-filter=D", BASE).splitlines() if p]
if deleted:
    fails.append(f"deleted files: {deleted[:10]}")
# Every changed path: regular file, same git mode as at BASE, not a symlink or submodule.
for line in git("diff", "--raw", "--no-renames", BASE).splitlines():
    m = re.match(r"^:(\d{6}) (\d{6}) \S+ \S+ (\S)\t(.+)$", line)
    if not m:
        continue
    old_mode, new_mode, status, path = m.groups()
    if status == "D":
        continue
    if status == "A" or old_mode != new_mode or new_mode not in ("100644", "100755"):
        fails.append(f"{path}: git mode {old_mode} -> {new_mode} (status {status}); only content edits of "
                     f"regular files are allowed")
for p in changed:
    fp = ROOT / p
    if fp.is_symlink() or (fp.exists() and not fp.is_file()):
        fails.append(f"{p}: not a regular file in the tree")
ruby_files = []
for p in changed:
    if p in CONFIG_FILES or p in deleted:
        continue
    if not RUBY_SOURCE.match(p):
        fails.append(f"{p}: not a Ruby source R2 may change (templates, bin/ and other files are out)")
    elif not allowed_cops(p):
        fails.append(f"{p}: changed, but BASE .rubocop_todo.yml lists it under no R2 cop")
    else:
        ruby_files.append(p)

work = ROOT / "tmp" / "r2-equiv"
shutil.rmtree(work, ignore_errors=True)
for d in ("base", "selftest/base", "selftest/tree"):
    (work / d).mkdir(parents=True)
for p in ruby_files:
    b = base_bytes(p)
    if b is None:
        fails.append(f"{p}: new file (R2 only edits existing files)")
        continue
    dst = work / "base" / p
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_bytes(b)
ruby_files = [p for p in ruby_files if (work / "base" / p).exists()]

# 1. self-test -------------------------------------------------------------------------------------
GC, RP, RR = "Style/GuardClause", "Style/RedundantParentheses", "Style/RedundantReturn"
HA, AF, BF = "Style/HashAsLastArrayItem", "Style/ArgumentsForwarding", "Naming/BlockForwarding"
SA, ES = "Style/SuperArguments", "Style/EmptyStringInsideInterpolation"
SELFTEST = [
    # (name, base, tree, allowed cops, expected verdict)
    ("mod.rb", "def f\n  if c\n    g\n  end\nend\n", "def f\n  g if c\nend\n", [], "SAME"),
    ("guard.rb", "def f\n  x\n  if c\n    g\n    h\n  end\nend\n",
     "def f\n  x\n  return unless c\n\n  g\n  h\nend\n", [GC], f"EXPLAINED {GC}"),
    ("guard_if.rb", "def f\n  unless c\n    g\n  end\nend\n", "def f\n  return if c\n\n  g\nend\n", [GC], f"EXPLAINED {GC}"),
    ("guard_mid.rb", "def f\n  if c\n    g\n  end\n  h\nend\n", "def f\n  return unless c\n\n  g\n  h\nend\n", [GC], "DIFF"),
    ("guard_blk.rb", "def f\n  a.each do\n    if c\n      g\n    end\n  end\nend\n",
     "def f\n  a.each do\n    return unless c\n\n    g\n  end\nend\n", [GC], "DIFF"),
    ("guard_else.rb", "def f\n  begin\n    if c\n      g\n    end\n  rescue E\n    1\n  else\n    2\n  end\nend\n",
     "def f\n  begin\n    return unless c\n\n    g\n  rescue E\n    1\n  else\n    2\n  end\nend\n", [GC], "DIFF"),
    ("guard_nogc.rb", "def f\n  if c\n    g\n  end\nend\n", "def f\n  return unless c\n\n  g\nend\n", [RR], "DIFF"),
    ("paren.rb", "x = (a || b)\ny = a && (b && c)\n", "x = a || b\ny = a && b && c\n", [RP], f"EXPLAINED {RP}"),
    ("paren_mix.rb", "y = a && (b || c)\n", "y = a && b || c\n", [RP], "DIFF"),
    ("paren_def.rb", "defined?((a))\n", "defined?(a)\n", [RP], "DIFF"),
    ("paren_lit.rb", "x = (a || 1)\n", "x = a || 2\n", [RP], "DIFF"),
    ("ret.rb", "def f\n  return g if c\nend\n", "def f\n  g if c\nend\n", [RR], f"EXPLAINED {RR}"),
    ("ret_mid.rb", "def f\n  return g if c\n  h\nend\n", "def f\n  g if c\n  h\nend\n", [RR], "DIFF"),
    ("ret_blk.rb", "def f\n  a.map { |x| return x }\nend\n", "def f\n  a.map { |x| x }\nend\n", [RR], "DIFF"),
    ("hash.rb", "x = [1, a: 2]\n", "x = [1, { a: 2 }]\n", [HA], f"EXPLAINED {HA}"),
    ("hash_splat.rb", "x = [1, **h]\n", "x = [1, { **h }]\n", [HA], "DIFF"),
    ("hash_call.rb", "f(1, a: 2)\n", "f(1, { a: 2 })\n", [HA], "DIFF"),
    ("fwd.rb", "def f(x, *args, &block)\n  g(x, *args, &block)\nend\n", "def f(x, *, &)\n  g(x, *, &)\nend\n",
     [AF], f"EXPLAINED {AF}"),
    ("fwd_used.rb", "def f(*args)\n  g(*args)\n  args.size\nend\n", "def f(*)\n  g(*)\n  0\nend\n", [AF], "DIFF"),
    ("fwd_bind.rb", "def f(*args)\n  g(*args)\n  binding\nend\n", "def f(*)\n  g(*)\n  binding\nend\n", [AF], "DIFF"),
    ("blk.rb", "def f(&block)\n  g(&block)\nend\n", "def f(&)\n  g(&)\nend\n", [BF], f"EXPLAINED {BF}"),
    ("blk_rest.rb", "def f(*args)\n  g(*args)\nend\n", "def f(*)\n  g(*)\nend\n", [BF], "DIFF"),
    ("super.rb", "def f(a, b)\n  super(a, b)\nend\n", "def f(a, b)\n  super\nend\n", [SA], f"EXPLAINED {SA}"),
    ("super_w.rb", "def f(a)\n  a = 1\n  super(a)\nend\n", "def f(a)\n  a = 1\n  super\nend\n", [SA], "DIFF"),
    ("super_opt.rb", "def f(a, b = 1)\n  super(a)\nend\n", "def f(a, b = 1)\n  super\nend\n", [SA], "DIFF"),
    ("interp.rb", "x = \"#{c ? 'a' : ''}b\"\n", "x = \"#{'a' if c}b\"\n", [ES], f"EXPLAINED {ES}"),
    ("interp_x.rb", "x = \"#{c ? 'a' : ' '}b\"\n", "x = \"#{'a' if c}b\"\n", [ES], "DIFF"),
    ("fwd_default.rb", "def f(x = local_variables, *args)\n  g(*args)\nend\n",
     "def f(x = local_variables, *)\n  g(*)\nend\n", [AF], "DIFF"),
    ("fwd_default_read.rb", "def f(*args, k: args)\n  g(*args)\nend\n", "def f(*, k: args)\n  g(*)\nend\n",
     [AF], "DIFF"),
    ("fwd_default_bind.rb", "def f(y = binding, &block)\n  g(&block)\nend\n", "def f(y = binding, &)\n  g(&)\nend\n",
     [BF], "DIFF"),
    ("fwd_default_ok.rb", "def f(y = 1, &block)\n  g(&block)\nend\n", "def f(y = 1, &)\n  g(&)\nend\n",
     [BF], f"EXPLAINED {BF}"),
    ("blank_no.rb", "def f\n  return unless x.present?\n\n  g\nend\n", "def f\n  return if x.blank?\n\n  g\nend\n",
     [GC], "DIFF"),
    ("lit.rb", "def f\n  if c\n    g(1)\n  end\nend\n", "def f\n  return unless c\n\n  g(2)\nend\n", [GC], "DIFF"),
    ("enc.rb", "# encoding: us-ascii\nx = (\"a\")\n", "x = \"a\"\n", [RP], "DIFF"),
    ("retpair.rb", "def f\n  if a\n    if c\n      return 1\n    else\n      return 2\n    end\n  end\n  3\nend\n",
     "def f\n  if a\n    return 1 if c\n\n    return 2\n  end\n  3\nend\n", [GC], f"EXPLAINED {GC}"),
    ("retpair_x.rb", "def f\n  if a\n    if c\n      return 1\n    else\n      g\n    end\n  end\n  3\nend\n",
     "def f\n  if a\n    return 1 if c\n\n    g\n  end\n  3\nend\n", [GC], "DIFF"),
    ("redis_eval.rb", "def f\n  if c\n    r.eval(s)\n  end\nend\n", "def f\n  return unless c\n\n  r.eval(s)\nend\n",
     [GC], f"EXPLAINED {GC}"),
    ("lines.rb", "def f\n  if c\n    caller\n  end\nend\n", "def f\n  return unless c\n\n  caller\nend\n", [GC], "LINES"),
]
lst = []
for name, b, t, cops, _ in SELFTEST:
    (work / "selftest" / "base" / name).write_text(b)
    (work / "selftest" / "tree" / name).write_text(t)
    lst.append(f"{name}\t{','.join(cops)}")
(work / "selftest.list").write_text("\n".join(lst) + "\n")
(work / "files.list").write_text("".join(f"{p}\t{','.join(allowed_cops(p))}\n" for p in ruby_files))

uid = f"{subprocess.run(['id', '-u'], capture_output=True, text=True).stdout.strip()}:" \
      f"{subprocess.run(['id', '-g'], capture_output=True, text=True).stdout.strip()}"


def run_canon(base_dir, tree_dir, list_file):
    cmd = ["docker", "run", "--rm", "--user", uid, "-e", "HOME=/tmp", "-v", f"{ROOT}:/app:ro",
           "-v", f"{HERE / 'r2_canon.rb'}:/r2_canon.rb:ro", "-w", "/app", image,
           "ruby", "/r2_canon.rb", base_dir, tree_dir, list_file]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        fails.append(f"r2_canon.rb exited {r.returncode}: {r.stderr.strip()[:300]}")
    return r.stdout.splitlines()


got = {}
for line in run_canon("/app/tmp/r2-equiv/selftest/base", "/app/tmp/r2-equiv/selftest/tree",
                      "/app/tmp/r2-equiv/selftest.list"):
    parts = line.split()
    verdict, name = parts[0], parts[1]
    text = verdict if verdict != "EXPLAINED" else f"EXPLAINED {parts[2] if len(parts) > 2 else ''}"
    if verdict in ("LINES", "NEWWARN") or name not in got:
        got[name] = text if verdict != "NEWWARN" else got.get(name, text)
for name, _, _, _, want in SELFTEST:
    if got.get(name) != want:
        fails.append(f"self-test {name}: checker says {got.get(name)!r}, expected {want!r}")

# 3. per-file verdicts -----------------------------------------------------------------------------
per_cop = {c: 0 for c in R2_COPS}
explained = same = 0
if ruby_files:
    for line in run_canon("/app/tmp/r2-equiv/base", "/app", "/app/tmp/r2-equiv/files.list"):
        parts = line.split(maxsplit=2)
        if parts[0] == "SAME":
            same += 1
        elif parts[0] == "EXPLAINED":
            explained += 1
            for c in (parts[2].split(",") if len(parts) > 2 else []):
                per_cop[c] = per_cop.get(c, 0) + 1
        else:
            fails.append(line)
    print(f"files: {len(ruby_files)} changed Ruby files, {same} SAME (layout/comments only), {explained} EXPLAINED")
    print("per cop (files whose difference needs that cop's rewrite): " +
          ", ".join(f"{c}={n}" for c, n in per_cop.items()))

# 4. NilClass not reopened (nil.to_s == "" for EmptyStringInsideInterpolation) ----------------------
for sample, want_hit in [("class NilClass\n", True), ("NilClass.class_eval do", True), ("refine NilClass do", True),
                         ("NilClass.prepend(M)", True), ("x.nil?", False), ("class NilClassifier", False)]:
    if bool(NILCLASS_PATCH.search(sample)) != want_hit:
        fails.append(f"self-test NilClass pattern on {sample!r}: expected hit={want_hit}")
r = subprocess.run(["git", "-C", str(ROOT), "grep", "-nF", "NilClass", "--", "app", "lib", "config"],
                   capture_output=True, text=True)
if r.returncode not in (0, 1):
    fails.append(f"git grep for NilClass patches failed: {r.stderr.strip()[:200]}")
hits = [ln for ln in r.stdout.splitlines() if NILCLASS_PATCH.search(ln.split(":", 2)[-1])]
if hits:
    fails.append(f"NilClass reopened in the app (EmptyStringInsideInterpolation rewrite unsound): {hits[:3]}")

# 5. config files ----------------------------------------------------------------------------------
tree_todo = (ROOT / ".rubocop_todo.yml").read_text(encoding="utf-8") if (ROOT / ".rubocop_todo.yml").exists() else ""
want = expected_todo(base_todo_text)
if tree_todo != want:
    fails.append(f".rubocop_todo.yml differs from BASE minus R2 sections plus TODO_ADDITIONS: "
                 f"{first_text_diff(want, tree_todo)}")
if (ROOT / ".rubocop.yml").read_text(encoding="utf-8") != (base_text(".rubocop.yml") or ""):
    fails.append(".rubocop.yml changed (R2 does not touch it)")

# 6. directives and ERB ----------------------------------------------------------------------------
for line in git("diff", "-U0", BASE, "--", ".rubocop.yml", ".rubocop_todo.yml").splitlines():
    if line.startswith("+") and not line.startswith("+++") and "<%" in line:
        fails.append(f"ERB tag added to a RuboCop config: {line[:160]}")
scope_files = set(base_todo.get("Style/DirectiveScope", []))
cur = None
removed_dirs, added_dirs = {}, {}
for line in git("diff", "-U0", BASE, "--", *ruby_files).splitlines() if ruby_files else []:
    if line.startswith("+++ b/"):
        cur = line[6:]
        continue
    if line.startswith(("---", "+++", "@@")) or not line[:1] in "+-":
        continue
    m = DIRECTIVE.match(line[1:])
    if "rubocop:" in line and not m:
        fails.append(f"{cur}: unrecognized rubocop directive change: {line[:160]}")
    if m:
        (added_dirs if line[0] == "+" else removed_dirs).setdefault(cur, []).append((m.group(1), m.group(2)))
for f, dirs in added_dirs.items():
    disabled = {c for kind, c in removed_dirs.get(f, []) if kind == "disable"}
    for kind, c in dirs:
        if f not in scope_files or kind != "disable-next" or c not in disabled:
            fails.append(f"{f}: directive added `rubocop:{kind} {c}` (only disable-next of a cop disabled "
                         f"at BASE, only in Style/DirectiveScope files)")
for f, dirs in removed_dirs.items():
    if f not in scope_files:
        fails.append(f"{f}: rubocop directive removed outside Style/DirectiveScope files: {dirs[:3]}")

for f in fails:
    print("FAIL:", f)
if fails:
    sys.exit(1)
print("R2 EQUIV PASS")
