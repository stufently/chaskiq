#!/usr/bin/env python3
"""Integrity probe for fork-updates-m14 (Ruby 3.3 -> 4.0.10, bundler 4.0.20).

Usage (from the repo root): python3 -I docs/specs/fork-updates-m14-probes/m14_integrity_probe.py <BASE_SHA>

Checks the working tree against BASE:
  1. every Ruby/bundler version spot says 4.0.10 / 4.0.20: Gemfile `ruby "4.0.10"`, .ruby-version,
     Gemfile.lock RUBY VERSION and BUNDLED WITH, Dockerfile and Dockerfile.development
     (ARG RUBY_VERSION), docker-compose.yml (RUBY_VERSION, BUNDLER_VERSION), hooks/build,
     .github/workflows/{anchore-analysis,dockerimage,docker-image-ghcr}.yml, bin/ci-local
     (RUBY_BUILDER_VERSION, RUBY_BUILDER_SHA256 of ruby-4.0.10-ubuntu-26.04-x64.tar.gz,
     BUNDLER_VERSION); no 3.3.x / 2.4.10 / 2.3.26 left in tracked files outside docs/,
     CHANGELOG.md, Gemfile.lock, spec/ and the JS tree;
  2. Gemfile differs from BASE only by the ruby line, the tzinfo-data platforms line
     (%i[windows jruby]) and added `gem "<bundled gem>"` lines;
  3. Gemfile.lock: gems that changed version, appeared or disappeared are in the allowlist
     (stringio, minitest and its new deps drb/prism, webmock, mustache, Ruby 4 bundled gems);
     only mingw platforms may disappear from PLATFORMS (with their platform gem variants);
     GIT/PATH sources unchanged; rack, rails, puma and rubocop versions unchanged;
  4. .rubocop.yml and .rubocop_todo.yml unchanged, no `rubocop:disable` added;
  6. docker-compose.yml mounts the volume bundle_ruby4 at /usr/local/bundle (a new name, so an old
     volume cannot hide the Ruby 4 gems); CHANGELOG.md has the operator note;
  5. existing spec files only gained lines (except spec lines listed in the spec), no spec file
     deleted or renamed, spec_helper, rails_helper, .rspec and spec/support untouched, no
     skip/pending added.
Prints one line per failure and "M14 INTEGRITY PASS" when everything holds.
"""
import pathlib
import re
import subprocess
import sys

if len(sys.argv) != 2:
    sys.exit("usage: m14_integrity_probe.py <BASE_SHA>")
BASE = sys.argv[1]
ROOT = pathlib.Path(subprocess.run(["git", "rev-parse", "--show-toplevel"], check=True,
                                   capture_output=True, text=True).stdout.strip())
RUBY = "4.0.10"
BUNDLER = "4.0.20"
BUILDER_SHA = "d08c941aa89ddf5aa6bf2228daa8de21af25bab8b68a6e9f24f933b1d4c6d7d7"
BUNDLED = {"csv", "ostruct", "cgi", "base64", "bigdecimal", "mutex_m", "drb", "observer", "nkf", "logger",
           "benchmark", "getoptlong", "resolv-replace", "rinda", "syslog", "abbrev", "racc", "fiddle",
           "pstore", "irb", "rdoc", "reline", "readline", "win32ole", "repl_type_completor", "prism"}
fails = []


def git(*args):
    return subprocess.run(["git", "-C", str(ROOT), *args], check=True, capture_output=True, text=True).stdout


def base_text(path):
    r = subprocess.run(["git", "-C", str(ROOT), "show", f"{BASE}:{path}"], capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else None


def cur_text(path):
    p = ROOT / path
    return p.read_text(encoding="utf-8") if p.exists() else ""


def need(path, pattern, what):
    if not re.search(pattern, cur_text(path), re.M):
        fails.append(f"{path}: {what}")


# 1. version spots
need("Gemfile", rf'^ruby "{re.escape(RUBY)}"$', f'expected ruby "{RUBY}"')
if cur_text(".ruby-version").strip() != RUBY:
    fails.append(f".ruby-version is {cur_text('.ruby-version').strip()!r}, expected {RUBY}")
need("Gemfile.lock", rf"^RUBY VERSION\n\s+ruby {re.escape(RUBY)}(p\d+)?$", f"RUBY VERSION must be ruby {RUBY}")
need("Gemfile.lock", rf"^BUNDLED WITH\n\s+{re.escape(BUNDLER)}$", f"BUNDLED WITH must be {BUNDLER}")
for path in ("Dockerfile", "Dockerfile.development"):
    need(path, rf"^ARG RUBY_VERSION={re.escape(RUBY)}$", f"expected ARG RUBY_VERSION={RUBY}")
need("docker-compose.yml", rf"RUBY_VERSION: '{re.escape(RUBY)}'", f"expected RUBY_VERSION: '{RUBY}'")
for path in ("hooks/build", ".github/workflows/anchore-analysis.yml", ".github/workflows/dockerimage.yml",
             ".github/workflows/docker-image-ghcr.yml"):
    need(path, rf"RUBY_VERSION={re.escape(RUBY)}\b", f"expected RUBY_VERSION={RUBY}")
need("bin/ci-local", rf"^RUBY_BUILDER_VERSION={re.escape(RUBY)}$", f"expected RUBY_BUILDER_VERSION={RUBY}")
need("bin/ci-local", rf"^RUBY_BUILDER_SHA256={BUILDER_SHA}$", "RUBY_BUILDER_SHA256 must be the digest of ruby-4.0.10-ubuntu-26.04-x64.tar.gz")
for path in ("docker-compose.yml", "hooks/build", ".github/workflows/anchore-analysis.yml",
             ".github/workflows/dockerimage.yml", ".github/workflows/docker-image-ghcr.yml", "bin/ci-local",
             "Dockerfile", "Dockerfile.development"):
    for no, line in enumerate(cur_text(path).splitlines(), 1):
        m = re.search(r"BUNDLER_VERSION[=:]\s*'?\"?([0-9][0-9.]*)", line)
        if m and m.group(1) != BUNDLER:
            fails.append(f"{path}:{no} BUNDLER_VERSION {m.group(1)}, expected {BUNDLER}")
stale = subprocess.run(["git", "-C", str(ROOT), "grep", "-nE", r"\b3\.3\.[0-9]+\b|\b2\.4\.10\b|\b2\.3\.26\b", "--",
                        ".", ":!docs", ":!CHANGELOG.md", ":!Gemfile", ":!Gemfile.lock", ":!yarn.lock", ":!package.json",
                        ":!spec", ":!app/javascript", ":!public"], capture_output=True, text=True).stdout
for line in stale.splitlines():
    fails.append(f"old Ruby/bundler version left: {line[:160]}")

# 2. Gemfile
bg = (base_text("Gemfile") or "").splitlines()
cg = cur_text("Gemfile").splitlines()
expected = []
for line in bg:
    if re.match(r'^ruby "3\.3\.\d+"$', line):
        line = f'ruby "{RUBY}"'
    if line.startswith('gem "tzinfo-data", platforms:'):
        line = 'gem "tzinfo-data", platforms: %i[windows jruby]'
    expected.append(line)
extra = list(cg)
for line in expected:
    if line in extra:
        extra.remove(line)
    else:
        fails.append(f"Gemfile: BASE line missing or changed: {line!r}")
for line in extra:
    m = re.match(r'^gem "([a-z0-9_-]+)"(, "[~><= 0-9.]+")*$', line)
    if line.strip() and not line.lstrip().startswith("#") and not (m and m.group(1) in BUNDLED):
        fails.append(f"Gemfile: added line is not a bundled gem: {line!r}")


# 3. Gemfile.lock
def specs(lock):
    out, section = {}, None
    for line in lock.splitlines():
        if re.match(r"^[A-Z]", line):
            section = line.strip()
        m = re.match(r"^    ([A-Za-z0-9_.-]+) \(([^)]+)\)$", line)
        if m and section in ("GEM", "GIT", "PATH"):
            ver = m.group(2)
            if re.search(r"mingw|mswin", ver):
                continue
            out.setdefault(m.group(1), set()).add(ver)
    return out


def block(lock, name):
    m = re.search(rf"^{name}\n((?:  .*\n)*)", lock, re.M)
    return [l.strip() for l in m.group(1).splitlines()] if m else []


bl, cl = base_text("Gemfile.lock") or "", cur_text("Gemfile.lock")
bs, cs = specs(bl), specs(cl)
ALLOWED = {"stringio", "minitest", "webmock", "mustache"} | BUNDLED
changed = sorted(n for n in set(bs) | set(cs) if bs.get(n) != cs.get(n))
bad = [n for n in changed if n not in ALLOWED]
if bad:
    fails.append(f"Gemfile.lock changes gems outside the allowlist: {bad}")
for n in ("rack", "rails", "puma", "rubocop", "rubocop-rails", "nokogiri", "scout_apm", "oauth"):
    if bs.get(n) != cs.get(n):
        fails.append(f"Gemfile.lock must keep {n} at {sorted(bs.get(n, []))}")
bp, cp = block(bl, "PLATFORMS"), block(cl, "PLATFORMS")
gone = [p for p in bp if p not in cp]
if [p for p in cp if p not in bp] or [p for p in gone if "mingw" not in p]:
    fails.append(f"PLATFORMS: only mingw platforms may be removed (removed {gone}, now {cp})")
for kind in ("GIT", "PATH"):
    if re.findall(rf"^{kind}\n  remote: .*$", bl, re.M) != re.findall(rf"^{kind}\n  remote: .*$", cl, re.M):
        fails.append(f"Gemfile.lock {kind} sources differ from BASE")

# 4. rubocop
for rel in (".rubocop.yml", ".rubocop_todo.yml"):
    if cur_text(rel) != (base_text(rel) or ""):
        fails.append(f"{rel} must not change (RuboCop version does not change in this milestone)")
for line in git("diff", "-U0", BASE, "--", ".", ":(exclude)docs/specs").splitlines():
    if line.startswith("+") and not line.startswith("+++") and "rubocop:disable" in line:
        fails.append(f"adds rubocop:disable: {line[1:].strip()}")

# 5. specs
for entry in [l for l in git("diff", "--name-status", BASE, "--", "spec", ".rspec").splitlines() if l]:
    status, *paths = entry.split("\t")
    rel = paths[-1]
    if rel in ("spec/spec_helper.rb", "spec/rails_helper.rb", ".rspec") or rel.startswith("spec/support/"):
        fails.append(f"{rel}: must not change ({status})")
        continue
    if status.startswith(("D", "R")):
        fails.append(f"{rel}: spec files must not be deleted or renamed ({status})")
        continue
    diff = git("diff", "-U0", BASE, "--", rel)
    if status.startswith("M") and [d for d in diff.splitlines() if d.startswith("-") and not d.startswith("---")]:
        fails.append(f"{rel}: existing lines changed or removed")
    for d in diff.splitlines():
        if d.startswith("+") and not d.startswith("+++") and re.search(r"\b(xit|xdescribe|xcontext|skip|pending)\b|:skip\b", d):
            fails.append(f"{rel}: adds skip/pending: {d[1:].strip()}")

# 6. compose: the volume over /usr/local/bundle gets a new name; CHANGELOG tells operators
mounts = re.findall(r"(?m)^    - ([A-Za-z0-9_]+):/usr/local/bundle$", cur_text("docker-compose.yml") or "")
old_mounts = re.findall(r"(?m)^    - ([A-Za-z0-9_]+):/usr/local/bundle$", base_text("docker-compose.yml") or "")
if mounts != ["bundle_ruby4"] or old_mounts == ["bundle_ruby4"]:
    fails.append(f"docker-compose.yml must mount volume bundle_ruby4 at /usr/local/bundle (now {mounts}, BASE {old_mounts})")
elif not re.search(r"(?m)^  bundle_ruby4:", cur_text("docker-compose.yml") or ""):
    fails.append("docker-compose.yml: volumes: has no bundle_ruby4 key")
changelog = git("diff", "-U0", BASE, "--", "CHANGELOG.md")
if "bundle_ruby4" not in changelog or "docker compose build" not in changelog:
    fails.append("CHANGELOG.md: no operator note about the bundle_ruby4 volume and `docker compose build`")

for f in fails:
    print(f"FAIL: {f}")
if fails:
    sys.exit(1)
print("M14 INTEGRITY PASS")
