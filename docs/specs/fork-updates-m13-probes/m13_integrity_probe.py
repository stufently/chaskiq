#!/usr/bin/env python3
"""Integrity probe for fork-updates-m13 (rack 2.2 -> 3).

Usage (from the repo root): python3 -I docs/specs/fork-updates-m13-probes/m13_integrity_probe.py <BASE_SHA>

Checks the working tree against BASE:
  1. Gemfile differs from BASE only in the rack line, which is now
     `gem "rack", "~> 3.2", ">= 3.2.8"`;
  2. Gemfile.lock: rack is 3.2.x >= 3.2.8; the only gems whose version changed, appeared or
     disappeared are rack, rack-session, rackup, rack-protection, omniauth, webrick (removed with
     rackup 1) and logger/base64 (new dependencies of rack-protection 4 / rack-session 2, only if
     added); GIT/PATH sources, PLATFORMS, RUBY VERSION and BUNDLED WITH are unchanged;
  3. no upper-case header name in the raw Rack responses of config/middleware/*.rb and lib/rack/*.rb;
  4. .rubocop.yml and .rubocop_todo.yml unchanged, no `rubocop:disable` added;
  5. existing spec files only gained lines, no spec file deleted or renamed, spec_helper,
     rails_helper, .rspec and spec/support untouched, no skip/pending added;
     spec/middleware/maintenance_mode_spec.rb exists;
  6. config/initializers/rack_forwarded.rb pins rack 2's forwarded header order (exact lines),
     spec/lib/rack_forwarded_spec.rb exists; docker-compose.yml only renames the `bundle` volume
     to `bundle_rack3`; CHANGELOG.md tells operators about it and `docker compose build`.
Prints one line per failure and "M13 INTEGRITY PASS" when everything holds.
"""
import pathlib
import re
import subprocess
import sys

if len(sys.argv) != 2:
    sys.exit("usage: m13_integrity_probe.py <BASE_SHA>")
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


def vtuple(v):
    return tuple(int(x) for x in re.findall(r"\d+", v))


# 1. Gemfile
OLD_RACK = re.compile(r'^gem "rack", "~> 2\.2", ">= 2\.2\.\d+"\n', re.M)
NEW_RACK = 'gem "rack", "~> 3.2", ">= 3.2.8"\n'
bg = base_text("Gemfile") or ""
if not OLD_RACK.search(bg):
    fails.append("BASE Gemfile has no rack 2.2 line (wrong BASE?)")
elif cur_text("Gemfile") != OLD_RACK.sub(NEW_RACK, bg, count=1):
    fails.append(f"Gemfile must differ from BASE only by: {NEW_RACK.strip()}")


# 2. Gemfile.lock
def specs(lock):
    out = {}
    section = None
    for line in lock.splitlines():
        if re.match(r"^[A-Z]", line):
            section = line.strip()
        m = re.match(r"^    ([A-Za-z0-9_.-]+) \(([^)]+)\)$", line)
        if m and section in ("GEM", "GIT", "PATH"):
            out.setdefault(m.group(1), set()).add(m.group(2))
    return out


def block(lock, name):
    m = re.search(rf"^{name}\n((?:  .*\n)*)", lock, re.M)
    return m.group(1) if m else None


bl, cl = base_text("Gemfile.lock") or "", cur_text("Gemfile.lock") or ""
bs, cs = specs(bl), specs(cl)
ALLOWED = {"rack", "rack-session", "rackup", "rack-protection", "omniauth", "webrick", "logger", "base64"}
changed = sorted(n for n in set(bs) | set(cs) if bs.get(n) != cs.get(n))
extra = [n for n in changed if n not in ALLOWED]
if extra:
    fails.append(f"Gemfile.lock changes gems outside the allowlist: {extra}")
for n in ("logger", "base64"):
    if n in bs and bs.get(n) != cs.get(n):
        fails.append(f"Gemfile.lock must not change the existing {n} version")
if "webrick" in cs and bs.get("webrick") != cs.get("webrick"):
    fails.append("webrick may only disappear, not change")
rack = sorted(cs.get("rack", set()))
if len(rack) != 1 or not rack[0].startswith("3.2.") or vtuple(rack[0]) < (3, 2, 8):
    fails.append(f"rack in Gemfile.lock is {rack}, expected one 3.2.x >= 3.2.8")
for n, major in (("rack-session", 2), ("rackup", 2), ("rack-protection", 4)):
    v = sorted(cs.get(n, set()))
    if not v or any(vtuple(x)[0] != major for x in v):
        fails.append(f"{n} in Gemfile.lock is {v}, expected {major}.x")
for name in ("PLATFORMS", "RUBY VERSION", "BUNDLED WITH"):
    if block(bl, name) != block(cl, name):
        fails.append(f"Gemfile.lock {name} differs from BASE")
for kind in ("GIT", "PATH"):
    if re.findall(rf"^{kind}\n  remote: .*$", bl, re.M) != re.findall(rf"^{kind}\n  remote: .*$", cl, re.M):
        fails.append(f"Gemfile.lock {kind} sources differ from BASE")

# 3. raw Rack header names
for rel in sorted([*(ROOT / "config/middleware").glob("*.rb"), *(ROOT / "lib/rack").glob("*.rb")]):
    for no, line in enumerate(rel.read_text(encoding="utf-8").splitlines(), 1):
        for key in re.findall(r"""["']([A-Za-z0-9-]+)["']\s*=>""", line.split("#", 1)[0]):
            if re.search(r"[A-Z]", key) and "-" in key or key in ("Location", "Server", "Vary"):
                fails.append(f"{rel.relative_to(ROOT)}:{no} upper-case response header name {key!r}")

# 4. rubocop
for rel in (".rubocop.yml", ".rubocop_todo.yml"):
    if cur_text(rel) != base_text(rel):
        fails.append(f"{rel} must not change")
for line in git("diff", "-U0", BASE, "--", ".", ":(exclude)docs/specs").splitlines():
    if line.startswith("+") and not line.startswith("+++") and "rubocop:disable" in line:
        fails.append(f"adds rubocop:disable: {line[1:].strip()}")

# 5. specs
if not (ROOT / "spec/middleware/maintenance_mode_spec.rb").exists():
    fails.append("spec/middleware/maintenance_mode_spec.rb missing")
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

# 6. forwarded headers keep rack 2's order; compose bundle volume renamed and nothing else
fwd = cur_text("config/initializers/rack_forwarded.rb") or ""
code = [l.strip() for l in fwd.splitlines() if l.strip() and not l.lstrip().startswith("#")]
want_fwd = ["Rack::Request.forwarded_priority = [:x_forwarded]",
            "Rack::Request.x_forwarded_proto_priority = %i[scheme proto]"]
if code != want_fwd:
    fails.append("config/initializers/rack_forwarded.rb must hold exactly: " + " / ".join(want_fwd))
if not (ROOT / "spec/lib/rack_forwarded_spec.rb").exists():
    fails.append("spec/lib/rack_forwarded_spec.rb missing")
compose_base = base_text("docker-compose.yml") or ""
want_compose = compose_base.replace("    - bundle:/usr/local/bundle\n", "    - bundle_rack3:/usr/local/bundle\n", 1)
want_compose = re.sub(r"(?m)^  bundle:", "  bundle_rack3:", want_compose, count=1)
if want_compose == compose_base or cur_text("docker-compose.yml") != want_compose:
    fails.append("docker-compose.yml: only `bundle` -> `bundle_rack3` (mount line and volumes key) may change")
changelog = git("diff", "-U0", BASE, "--", "CHANGELOG.md")
if "bundle_rack3" not in changelog or "docker compose build" not in changelog:
    fails.append("CHANGELOG.md: no operator note about the bundle_rack3 volume and `docker compose build`")

for f in fails:
    print(f"FAIL: {f}")
if fails:
    sys.exit(1)
print("M13 INTEGRITY PASS")
