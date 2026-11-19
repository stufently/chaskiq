#!/usr/bin/env python3
"""Static integrity probe for fork-updates-m6 (Rails 8.1 upgrade).

Usage (from the repo root): python3 -I m6_integrity_probe.py <BASE>
Checks the working tree against BASE:
  - framework defaults stay: config.load_defaults 7.0, new_framework_defaults_* untouched;
  - Rails 8 removals handled: no keyword-style `enum name: {...}` in app/ and lib/,
    no Dotenv::Railtie, spec helper uses fixture_paths;
  - Gemfile changed only on the allowed declarations (rails, uri, acts-as-taggable-on,
    mini_magick, optional ruby-vips);
  - existing spec lines are not removed or changed, except the single fixture_path line;
    no new files in spec/support, no new skips;
  - invariants of m1..m4 are still in the tree.
"""
import re
import subprocess
import sys
from pathlib import Path

if len(sys.argv) != 2:
    sys.exit("usage: m6_integrity_probe.py <BASE>")
BASE = sys.argv[1]
fails = []


def git(*args):
    r = subprocess.run(["git", *args], capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(f"git {' '.join(args)} failed: {r.stderr.strip()}")
    return r.stdout


def read(path):
    p = Path(path)
    return p.read_text(encoding="utf-8") if p.exists() else ""


def diff_lines(path):
    """Removed and added content lines of path between BASE and the working tree."""
    out = git("diff", "--no-color", "-U0", BASE, "--", path)
    removed, added = [], []
    for line in out.splitlines():
        if line.startswith("---") or line.startswith("+++"):
            continue
        if line.startswith("-"):
            removed.append(line[1:])
        elif line.startswith("+"):
            added.append(line[1:])
    return removed, added


app_rb = read("config/application.rb")
if not re.search(r"^\s*config\.load_defaults 7\.0\s*$", app_rb, re.M):
    fails.append("config/application.rb must keep config.load_defaults 7.0 (defaults move in the next milestone)")
if "Dotenv::Railtie" in app_rb:
    fails.append("config/application.rb still uses the deprecated Dotenv::Railtie")
for f in git("diff", "--name-only", BASE, "--", "config/initializers/").split():
    if "new_framework_defaults" in f:
        fails.append(f"{f} changed (framework defaults are out of scope)")

enum_kw = re.compile(r"^\s*enum\s+[a-z_]+:\s*[\[{]", re.M)
for root in ("app", "lib"):
    for p in Path(root).rglob("*.rb"):
        if enum_kw.search(p.read_text(encoding="utf-8", errors="replace")):
            fails.append(f"{p}: keyword-style enum (removed in Rails 8), use enum :name, {{...}}")

helper = read("spec/rails_helper.rb")
if re.search(r"^\s*config\.fixture_path\s*=", helper, re.M):
    fails.append("spec/rails_helper.rb still sets the singular fixture_path")
if not re.search(r"^\s*config\.fixture_paths\s*=", helper, re.M):
    fails.append("spec/rails_helper.rb must set config.fixture_paths")

removed, added = diff_lines("Gemfile")
allowed_removed = [
    re.compile(r'^gem "rails", "7\.2\.1\.1"'),
    re.compile(r'^gem "uri", "0\.12\.5"'),
    re.compile(r'^gem "acts-as-taggable-on", github: "mbleigh/acts-as-taggable-on"'),
    re.compile(r'^gem "mini_magick", "~> 4\.8"'),
]
allowed_added = [
    re.compile(r'^gem "rails", "~> 8\.1(\.\d+)*"(, ">= 8\.1\.4\.1")?( *#.*)?$'),
    re.compile(r'^gem "uri", "(~>|>=) 1\.\d+(\.\d+)?"( *#.*)?$'),
    re.compile(r'^gem "acts-as-taggable-on", "(~>|>=) 13(\.\d+)*"( *#.*)?$'),
    re.compile(r'^gem "mini_magick", "(~>|>=) 5\.\d+(\.\d+)?"( *#.*)?$'),
    re.compile(r'^gem "ruby-vips", "(~>|>=) 2\.\d+(\.\d+)?"( *#.*)?$'),
]
for line in removed:
    if line.strip() and not any(r.search(line) for r in allowed_removed):
        fails.append(f"Gemfile: line removed or changed outside the allowed set: {line!r}")
for line in added:
    if line.strip() and not any(r.search(line) for r in allowed_added):
        fails.append(f"Gemfile: line added outside the allowed set: {line!r}")

FIXTURE_OLD = '  config.fixture_path = Rails.root.join("spec/fixtures")'
skip_re = re.compile(r"^\s*(xit|xdescribe|xcontext|skip|pending)\b|:skip\b|skip:\s*true")
for f in git("diff", "--name-only", "--diff-filter=DMR", BASE, "--", "spec/").split():
    rem, add = diff_lines(f)
    for line in rem:
        if f == "spec/rails_helper.rb" and line == FIXTURE_OLD:
            continue
        if line.strip():
            fails.append(f"{f}: existing spec line removed or changed: {line!r}")
    for line in add:
        if skip_re.search(line):
            fails.append(f"{f}: new skip/pending: {line!r}")
for f in git("diff", "--name-only", "--diff-filter=A", BASE, "--", "spec/support/").split():
    fails.append(f"new file in spec/support: {f}")
for f in ("spec/spec_helper.rb", ".rspec"):
    if git("diff", "--name-only", BASE, "--", f).strip():
        fails.append(f"{f} changed")

invariants = [
    ("config/initializers/rack_attack.rb", 'Rack::Attack.throttle("logins/ip", limit: 20, period: 1.hour)'),
    ("app/services/message_apis/block_manager.rb", "def self.absolute_url"),
    ("app/services/message_apis/slack/api.rb", "def escape_mrkdwn"),
    ("app/services/message_apis/slack/api.rb", "verbatim: true"),
    ("docker-compose.yml", "image: redis:8.10-alpine"),
]
for env in ("production", "staging", "development"):
    invariants.append((f"config/environments/{env}.rb", "authentication: (:login unless ENV['SMTP_USERNAME'].to_s.empty?)"))
    invariants.append((f"config/environments/{env}.rb", "config.action_mailer.ses_settings = "))
for path, needle in invariants:
    if needle not in read(path):
        fails.append(f"{path}: invariant of m1..m4 missing: {needle!r}")
for env in ("production", "staging", "development"):
    if "add_action_mailer_delivery_method" in read(f"config/environments/{env}.rb"):
        fails.append(f"config/environments/{env}.rb: removed aws-sdk-rails 4 API is back")
if "node_modules" in read("config/initializers/assets.rb"):
    fails.append("config/initializers/assets.rb: node_modules is back in the asset paths")

if fails:
    print("\n".join(fails))
    sys.exit(1)
print("M6 INTEGRITY PROBE PASS")
