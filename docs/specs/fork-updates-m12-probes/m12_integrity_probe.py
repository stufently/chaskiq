#!/usr/bin/env python3
"""Integrity probe for fork-updates-m12 (third-party deprecations).

Usage (from the repo root): python3 -I docs/specs/fork-updates-m12-probes/m12_integrity_probe.py <BASE_SHA>

Checks the working tree against BASE:
  1. Gemfile = BASE minus the nightfury git line; Gemfile.lock = BASE minus the nightfury GIT
     block and its DEPENDENCIES entry (no other gem moves, no new git/path source);
  2. Nightfury is vendored under vendor/nightfury/ (lib/ of the gem, LICENSE with the MIT notice);
     no Redis.current and no string class_eval there; config/initializers/nightfury.rb is exactly
     the three code lines of the spec (Nightfury.redis = Redis.new, the BASE namespace line);
  3. no Redis.current and no /__cypress__/ route anywhere in tracked files outside docs/;
     cypress_helper.rb renamed to e2e_helper.rb unchanged; config/redis/shared.yml only gains a
     staging entry; config/initializers/redis.rb changes comments only;
  4. cypress-on-rails is configured with install_folder (no cypress_folder);
  5. .rubocop.yml only switches `require: rubocop-rails` to `plugins: rubocop-rails`;
     .rubocop_todo.yml untouched; no `rubocop:disable` added anywhere;
  6. specs: no rspec-mocks :should syntax left (stub, any_instance, should_receive, should,
     stub_chain, unstub); spec/spec_helper.rb only gains the `mocks.syntax = :expect` block;
     changed lines of existing spec files are old-syntax conversions (or the raise_exception line
     of app_user_spec.rb); stub/expectation chains (and_return, and_raise, with, ...) are not
     lost; no spec file deleted or renamed, no new file in spec/support, no skip/pending added;
     spec/lib/nightfury_spec.rb and spec/lib/rack/health_check_spec.rb exist.
Prints one line per failure and "M12 INTEGRITY PASS" when everything holds.
"""
import pathlib
import re
import subprocess
import sys

if len(sys.argv) != 2:
    sys.exit("usage: m12_integrity_probe.py <BASE_SHA>")
BASE = sys.argv[1]
ROOT = pathlib.Path(subprocess.run(["git", "rev-parse", "--show-toplevel"], check=True,
                                   capture_output=True, text=True).stdout.strip())
fails = []


def git(*args):
    return subprocess.run(["git", "-C", str(ROOT), *args], check=True, capture_output=True, text=True).stdout


def base_text(path):
    r = subprocess.run(["git", "-C", str(ROOT), "show", f"{BASE}:{path}"], capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else None


def cur_text(path):
    p = ROOT / path
    return p.read_text(encoding="utf-8") if p.exists() else None


def code(line):
    return line.split("#", 1)[0]


# 1. Gemfile / Gemfile.lock
NF_LINE = 'gem "nightfury", github: "michelson/nightfury" # "~> 1.0"\n'
bg = base_text("Gemfile")
if bg is None or NF_LINE not in bg:
    fails.append("BASE Gemfile has no nightfury git line (wrong BASE?)")
elif cur_text("Gemfile") != bg.replace(NF_LINE, "", 1):
    fails.append("Gemfile differs from BASE by more than the removed nightfury line")
bl = base_text("Gemfile.lock") or ""
block = re.search(r"GIT\n  remote: https://github\.com/michelson/nightfury\.git\n(?:  .*\n|    .*\n|      .*\n)*\n", bl)
if not block or "\n  nightfury!\n" not in bl:
    fails.append("BASE Gemfile.lock has no nightfury GIT block (wrong BASE?)")
else:
    expected = bl.replace(block.group(0), "", 1).replace("\n  nightfury!\n", "\n", 1)
    if cur_text("Gemfile.lock") != expected:
        fails.append("Gemfile.lock differs from BASE by more than the removed nightfury block and dependency")

# 2. vendored Nightfury
V = "vendor/nightfury/lib/"
NF_FILES = [V + f for f in ("nightfury.rb", "nightfury/version.rb", "nightfury/identity.rb", "nightfury/metric.rb",
                            "nightfury/metric/value.rb", "nightfury/metric/time_series.rb",
                            "nightfury/metric/count_time_series.rb", "nightfury/metric/avg_time_series.rb")]
for rel in NF_FILES:
    t = cur_text(rel)
    if t is None:
        fails.append(f"{rel} missing (vendored Nightfury)")
        continue
    for no, line in enumerate(t.splitlines(), 1):
        if "Redis.current" in code(line):
            fails.append(f"{rel}:{no} uses Redis.current")
        if re.search(r"class_eval\s*(\(|<<|\s[\"'%])", code(line)) or re.search(r"\beval\s*\(", code(line)):
            fails.append(f"{rel}:{no} string eval: {line.strip()}")
lic = cur_text("vendor/nightfury/LICENSE") or ""
if "Avinasha Shastry" not in lic or "MIT" not in lic:
    fails.append("vendor/nightfury/LICENSE must keep the MIT notice of nightfury (Copyright (c) 2012 Avinasha Shastry)")
init = [l for l in (cur_text("config/initializers/nightfury.rb") or "").splitlines() if l.strip() and not l.lstrip().startswith("#")]
want = ['require Rails.root.join("vendor/nightfury/lib/nightfury").to_s', 'Nightfury.redis = Redis.new',
        'Nightfury.redis.namespace = "nf-#{Rails.env}"']
if init != want:
    fails.append(f"config/initializers/nightfury.rb code lines {init!r}, expected {want!r}")

# 3. Redis.current anywhere in the repository (code, comments, JS, e2e), docs/ excluded
hits = subprocess.run(["git", "-C", str(ROOT), "grep", "-n", "Redis\\.current", "--", ".", ":!docs"],
                      capture_output=True, text=True).stdout
for line in hits.splitlines():
    fails.append(f"Redis.current left: {line[:160]}")
cy_hits = subprocess.run(["git", "-C", str(ROOT), "grep", "-n", "__cypress__", "--", ".", ":!docs"],
                         capture_output=True, text=True).stdout
for line in cy_hits.splitlines():
    fails.append(f"deprecated /__cypress__/command route left: {line[:160]}")
if (ROOT / "spec/cypress/cypress_helper.rb").exists() or cur_text("spec/cypress/e2e_helper.rb") != base_text("spec/cypress/cypress_helper.rb"):
    fails.append("spec/cypress/cypress_helper.rb must be renamed to spec/cypress/e2e_helper.rb unchanged")
shared = base_text("config/redis/shared.yml") or ""
if cur_text("config/redis/shared.yml") != shared.replace("development: &development", "staging:\n  <<: *production\n\ndevelopment: &development", 1):
    fails.append("config/redis/shared.yml must only gain `staging:\\n  <<: *production` before development")
def code_lines(text):
    return [l for l in (text or "").splitlines() if l.strip() and not l.lstrip().startswith("#")]
if code_lines(cur_text("config/initializers/redis.rb")) != code_lines(base_text("config/initializers/redis.rb")):
    fails.append("config/initializers/redis.rb: only comments may change")

# 4. cypress
cy = cur_text("config/initializers/cypress_on_rails.rb") or ""
if "cypress_folder" in cy or "c.install_folder" not in cy:
    fails.append("config/initializers/cypress_on_rails.rb must set install_folder, not cypress_folder")

# 5. rubocop config
br = base_text(".rubocop.yml") or ""
if cur_text(".rubocop.yml") != br.replace("require:\n  - rubocop-rails\n", "plugins:\n  - rubocop-rails\n", 1) or "require:\n  - rubocop-rails\n" not in br:
    fails.append(".rubocop.yml must differ from BASE only by require: -> plugins: for rubocop-rails")
if cur_text(".rubocop_todo.yml") != base_text(".rubocop_todo.yml"):
    fails.append(".rubocop_todo.yml must not change")
for line in git("diff", "-U0", BASE, "--", ".", ":(exclude)docs/specs").splitlines():
    if line.startswith("+") and not line.startswith("+++") and "rubocop:disable" in line:
        fails.append(f"adds rubocop:disable: {line[1:].strip()}")

# 6. specs
OLD = re.compile(r"\.(stub|stub_chain|unstub|should_receive|should_not_receive|any_instance)\b|\.should(_not)?\b")
for path in sorted((ROOT / "spec").rglob("*.rb")):
    rel = path.relative_to(ROOT).as_posix()
    for no, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if OLD.search(code(line)):
            fails.append(f"{rel}:{no} old :should syntax left: {line.strip()}")
for rel in ("spec/lib/nightfury_spec.rb", "spec/lib/rack/health_check_spec.rb", "spec/jobs/offline_checker_presence_spec.rb"):
    if not (ROOT / rel).exists():
        fails.append(f"{rel} missing")
helper = git("diff", "-U0", BASE, "--", "spec/spec_helper.rb")
h_removed = [d for d in helper.splitlines() if d.startswith("-") and not d.startswith("---")]
h_added = [d[1:].strip() for d in helper.splitlines() if d.startswith("+") and not d.startswith("+++")]
if h_removed or sorted(h_added) != sorted(["config.mock_with :rspec do |mocks|", "mocks.syntax = :expect", "end"]):
    fails.append(f"spec/spec_helper.rb must only gain the mocks.syntax = :expect block (removed {len(h_removed)}, added {h_added!r})")
if git("diff", "--name-only", BASE, "--", ".rspec", "spec/rails_helper.rb").strip():
    fails.append(".rspec / spec/rails_helper.rb must not change")
CONT = re.compile(r"^\s*\.(stub|and_return|and_raise|and_call_original|and_yield|with|once|twice|exactly|at_least|at_most|times)\b")
RAISE = "expect { app.merge_contact(from: app_user, to: lead) }.to raise_exception"
CHAIN = ["and_return", "and_raise", "and_call_original", "and_yield", ".with(", ".once", ".twice", ".exactly("]
for entry in [l for l in git("diff", "--name-status", BASE, "--", "spec").splitlines() if l]:
    status, *paths = entry.split("\t")
    rel = paths[-1]
    if status.startswith("R") and paths == ["spec/cypress/cypress_helper.rb", "spec/cypress/e2e_helper.rb"]:
        continue
    if rel.startswith("spec/cypress/") and status.startswith("M"):
        diff = git("diff", "-U0", BASE, "--", rel)
        removed = [d[1:] for d in diff.splitlines() if d.startswith("-") and not d.startswith("---")]
        added = [d[1:] for d in diff.splitlines() if d.startswith("+") and not d.startswith("+++")]
        conv = [re.sub(r'Redis\.current\.del\(("[^"]+")\)', r'Redis::Objects.redis.with { |r| r.del(\1) }',
                       l.replace("/__cypress__/command", "/__e2e__/command")) for l in removed]
        if sorted(conv) != sorted(added):
            fails.append(f"{rel}: cypress change other than /__e2e__/command and Redis::Objects.redis del")
        continue
    if status.startswith(("D", "R")):
        fails.append(f"{rel}: spec files must not be deleted or renamed ({status})")
        continue
    if status.startswith("A") and rel.startswith("spec/support/"):
        fails.append(f"{rel}: no new files in spec/support")
    diff = git("diff", "-U0", BASE, "--", rel)
    added = [d[1:] for d in diff.splitlines() if d.startswith("+") and not d.startswith("+++")]
    for line in added:
        if re.search(r"\b(xit|xdescribe|xcontext|skip|pending)\b|:skip\b", line):
            fails.append(f"{rel}: adds skip/pending: {line.strip()}")
    if not status.startswith("M") or rel == "spec/spec_helper.rb":
        continue
    for d in diff.splitlines():
        if d.startswith("-") and not d.startswith("---"):
            line = d[1:]
            if not (OLD.search(line) or CONT.search(line) or line.strip() == RAISE):
                fails.append(f"{rel}: changed line is not an old-syntax conversion: {line.strip()}")
    old, new = base_text(rel) or "", cur_text(rel) or ""
    for tok in CHAIN:
        if new.count(tok) < old.count(tok):
            fails.append(f"{rel}: '{tok}' count dropped {old.count(tok)} -> {new.count(tok)}")
    exp_old = sum(old.count(k) for k in ("should_receive", "expect_any_instance_of", "expect(", "expect {", "expect do"))
    exp_new = sum(new.count(k) for k in ("should_receive", "expect_any_instance_of", "expect(", "expect {", "expect do"))
    if exp_new < exp_old:
        fails.append(f"{rel}: expectations dropped {exp_old} -> {exp_new}")

for f in fails:
    print(f"FAIL: {f}")
if fails:
    sys.exit(1)
print("M12 INTEGRITY PASS")
