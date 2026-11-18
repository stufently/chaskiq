"""Probe for fork-updates-m3: dependency drift, test-suite integrity and carried invariants.

Usage: python3 -I docs/specs/fork-updates-m3-probes/m3_integrity_probe.py <BASE_SHA>  (clone root)
Fails on:
- Gemfile, Gemfile.lock, package.json or yarn.lock differ from BASE (no bumps in this milestone);
- spec/: a file deleted or renamed; a line removed from an existing spec file (existing files
  may only gain lines); a new file that is not *_spec.rb, or lives in spec/support/, or is
  rails_helper/spec_helper; .rspec changed; an added line under spec/ introducing
  skip/pending/x-prefixed examples, skip/pending metadata, require "webmock/rspec",
  RSpec.configure or global net-connect switches; any change to spec/rails_helper.rb,
  spec/spec_helper.rb or spec/support/;
- m1/m2 invariants gone: rack-attack logins/ip throttle literal 20/1.hour, Devise
  notification flags, Agent#send_devise_notification, no "use Rack::Attack" in config.ru,
  Slack upstream #917 user_scope, no Aws::Rails.add_action_mailer_delivery_method in any
  config/environments/*.rb;
- m3 shape: JSON.parse(...)["blocks"] left in the five outgoing plugins; Faraday-1-only calls
  (conn.authorization / conn.basic_auth / conn.token_auth / request :basic_auth|:token_auth)
  in app/ or lib/ outside comments; node_modules still added to config.assets.paths
  (excluded_paths is fine).
"""
import re
import subprocess
import sys

SKIP_RE = re.compile(r"^\s*(xit|xdescribe|xcontext|xspecify|xexample|xscenario|skip|pending)\b"
                     r"|\b(skip|pending)\s*:|:skip\b|:pending\b|\bskip\s*\(|\bpending\s*\(")
GLOBAL_RE = re.compile(r"webmock/rspec|RSpec\.configure|disable_net_connect!|allow_net_connect!")
PLUGINS = ("telegram", "message_bird", "telnyx_sms", "vonage", "slack")


def git(*args):
    return subprocess.run(["git", *args], check=True, capture_output=True).stdout.decode("utf-8", "replace")


def code_lines(path):
    for n, line in enumerate(open(path, encoding="utf-8", errors="replace"), 1):
        if not line.lstrip().startswith("#"):
            yield n, line


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: m3_integrity_probe.py <BASE_SHA>")
    base = sys.argv[1]
    fails = []

    for f in ("Gemfile", "Gemfile.lock", "package.json", "yarn.lock", ".rspec"):
        if git("diff", "--name-only", base, "--", f).strip():
            fails.append(f"{f} changed")

    for row in git("diff", "--name-status", "-M", base, "--", "spec").splitlines():
        status, *paths = row.split("\t")
        if status[0] in "DRC":
            fails.append(f"spec file deleted/renamed/copied: {row}")
        elif status[0] == "A":
            p = paths[0]
            if (not p.endswith("_spec.rb") or p.startswith("spec/support/")
                    or p in ("spec/rails_helper.rb", "spec/spec_helper.rb")):
                fails.append(f"new spec file not allowed: {p}")
    for path in git("diff", "--name-only", base, "--", "spec/rails_helper.rb", "spec/spec_helper.rb",
                    "spec/support").splitlines():
        fails.append(f"test configuration file changed: {path}")
    for row in git("diff", "--numstat", base, "--", "spec").splitlines():
        _added, removed, path = row.split("\t", 2)
        if removed != "0" and git("ls-tree", "--name-only", base, "--", path).strip():
            fails.append(f"lines removed from existing spec file {path} ({removed})")

    current = None
    for line in git("diff", "--no-color", "-U0", base, "--", "spec").splitlines():
        if line.startswith("+++ "):
            current = line[6:]
            continue
        if line.startswith("+") and not line.startswith("+++"):
            if SKIP_RE.search(line[1:]):
                fails.append(f"skip/pending added in {current}: {line[1:80]!r}")
            if GLOBAL_RE.search(line[1:]):
                fails.append(f"global test configuration added in {current}: {line[1:80]!r}")

    slack = "app/services/message_apis/slack/api.rb"
    if 'user_scope: "channels:history,channels:write,channels:read"' not in open(slack, encoding="utf-8").read():
        fails.append("slack plugin: upstream #917 reduced user_scope missing")
    ra = open("config/initializers/rack_attack.rb", encoding="utf-8").read()
    if not re.search(r'throttle\(\s*"logins/ip",\s*limit:\s*20,\s*period:\s*1\.hour', ra):
        fails.append("rack-attack logins/ip throttle literal limit: 20, period: 1.hour missing")
    dv = open("config/initializers/devise.rb", encoding="utf-8").read()
    for flag in ("send_email_changed_notification", "send_password_change_notification"):
        if not re.search(rf"^\s*config\.{flag}\s*=\s*true", dv, re.M):
            fails.append(f"devise {flag} not enabled")
    if "def send_devise_notification" not in open("app/models/agent.rb", encoding="utf-8").read():
        fails.append("Agent#send_devise_notification missing")
    if re.search(r"^\s*use\s+Rack::Attack", open("config.ru", encoding="utf-8").read(), re.M):
        fails.append("config.ru inserts Rack::Attack")
    for env in git("ls-files", "config/environments").split():
        if re.search(r"^\s*Aws::Rails\.add_action_mailer_delivery_method", open(env, encoding="utf-8").read(), re.M):
            fails.append(f"{env} still calls Aws::Rails.add_action_mailer_delivery_method")

    for p in PLUGINS:
        path = f"app/services/message_apis/{p}/api.rb"
        text = "".join(l for _, l in code_lines(path))
        if re.search(r"JSON\.parse\(\s*[^()]*\)\s*\[\s*[\"']blocks[\"']\s*\]", text):
            fails.append(f"{path}: still parses serialized_content as JSON blocks")
    faraday1 = re.compile(r"\.\s*(authorization|basic_auth|token_auth)\b(?!\s*=)|request\s*\(?\s*:(basic_auth|token_auth)\b")
    for path in git("ls-files", "app", "lib").split():
        if not path.endswith(".rb"):
            continue
        for n, line in code_lines(path):
            if faraday1.search(line) and "request :authorization" not in line and "request(:authorization" not in line:
                fails.append(f"Faraday-1-only call in {path}:{n}: {line.strip()[:80]}")
    for n, line in code_lines("config/initializers/assets.rb"):
        if "node_modules" in line and re.search(r"assets\.paths|\bpaths\s*(<<|\+=|\.push|\.unshift|\.append)", line):
            fails.append(f"config/initializers/assets.rb:{n} still puts node_modules on the asset path")

    if fails:
        print("\n".join(fails))
        sys.exit(1)
    print("M3 INTEGRITY PROBE PASS")


main()
