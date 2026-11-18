"""Probe for fork-updates-m2: dependency drift, test-suite integrity and m1 invariants.

Usage: python3 -I docs/specs/fork-updates-m2-probes/m2_integrity_probe.py <BASE_SHA>  (clone root)
Fails on:
- Gemfile.lock: a gem present at BASE changed version or vanished (except aws-* gems);
  a new gem not in NEW_GEMS_ALLOWED; BUNDLED WITH changed;
- package.json or yarn.lock differ from BASE;
- spec/: a file deleted or renamed; an existing spec file modified other than
  SPEC_EDIT_ALLOWED; an added line under spec/ introducing skip/pending/x-prefixed
  examples or skip/pending metadata;
- spec/: a new file added (filters/config could hide examples);
- campaign example 'will render subscriber attributes' still uses Faker, does not build a
  subscriber named Dee O'Keefe, or does not expect(...mustache_template_for...) to include
  the escaped 'Dee O&#39;Keefe';
- slack plugin without the upstream #917 reduced OAuth user_scope;
- m1 security invariants gone: rack-attack throttle 20/hour, Devise notification flags,
  queued Devise notifications in Agent, no "use Rack::Attack" in config.ru;
- config/environments/*.rb still call Aws::Rails.add_action_mailer_delivery_method.
"""
import re
import subprocess
import sys

NEW_GEMS_ALLOWED = {"aws-actionmailer-ses", "aws-sdk-ses", "aws-sdk-sesv2",
                    "faraday-multipart", "multipart-post"}
SPEC_EDIT_ALLOWED = {"spec/models/campaign_spec.rb", "spec/requests/rack_attack_spec.rb"}  # edits only, no new files
SKIP_RE =re.compile(r"^\s*(xit|xdescribe|xcontext|xspecify|xexample|xscenario|skip|pending)\b"
                     r"|\b(skip|pending)\s*:|:skip\b|:pending\b|\bskip\s*\(|\bpending\s*\(")


def git(*args):
    return subprocess.run(["git", *args], check=True, capture_output=True).stdout.decode("utf-8", "replace")


def lock_specs(text):
    out = {}
    for m in re.finditer(r"^    ([A-Za-z0-9_.\-]+) \(([^)]+)\)$", text, re.M):
        out.setdefault(m[1], m[2])
    return out


def bundled_with(text):
    m = re.search(r"^BUNDLED WITH\n\s+(\S+)", text, re.M)
    return m[1] if m else None


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: m2_integrity_probe.py <BASE_SHA>")
    base = sys.argv[1]
    fails = []

    old_lock, new_lock = git("show", f"{base}:Gemfile.lock"), open("Gemfile.lock", encoding="utf-8").read()
    old, new = lock_specs(old_lock), lock_specs(new_lock)
    for name, ver in sorted(old.items()):
        if name.startswith("aws-"):
            continue
        if name not in new:
            fails.append(f"gem {name} removed from Gemfile.lock")
        elif new[name] != ver:
            fails.append(f"gem {name} changed {ver} -> {new[name]}")
    for name in sorted(set(new) - set(old)):
        if name not in NEW_GEMS_ALLOWED:
            fails.append(f"new gem {name} ({new[name]}) not allowed")
    if bundled_with(old_lock) != bundled_with(new_lock):
        fails.append("BUNDLED WITH changed")

    for f in ("package.json", "yarn.lock"):
        if git("diff", "--name-only", f"{base}...HEAD", "--", f).strip():
            fails.append(f"{f} changed")

    for row in git("diff", "--name-status", "-M", f"{base}...HEAD", "--", "spec").splitlines():
        status, *paths = row.split("\t")
        if status[0] in "DRAC":
            fails.append(f"spec file deleted/renamed/added: {row}")
        elif status[0] == "M" and paths[0] not in SPEC_EDIT_ALLOWED:
            fails.append(f"existing spec file modified: {paths[0]}")

    current = None
    for line in git("diff", "--no-color", "-U0", f"{base}...HEAD", "--", "spec").splitlines():
        if line.startswith("+++ "):
            current = line[6:]
            continue
        if line.startswith("+") and not line.startswith("+++") and SKIP_RE.search(line[1:]):
            fails.append(f"skip/pending added in {current}: {line[1:80]!r}")

    camp = open("spec/models/campaign_spec.rb", encoding="utf-8").read().splitlines()
    block = None
    for i, line in enumerate(camp):
        m = re.match(r'^(\s*)it "will render subscriber attributes" do\s*$', line)
        if m:
            indent, body = m[1], []
            for nxt in camp[i + 1:]:
                if re.match(rf"^{indent}end\s*$", nxt):
                    block = body
                    break
                body.append(nxt)
            break
    if block is None:
        fails.append("campaign_spec: example 'will render subscriber attributes' not found")
    else:
        code = [l.split("#", 1)[0] if not re.search(r'"[^"]*#', l) else l for l in block]
        code = [l for l in code if l.strip() and not l.strip().startswith("#")]
        joined = "\n".join(code)
        if "Faker" in joined:
            fails.append("campaign_spec: render example still uses Faker")
        if not re.search(r"""["']Dee O'Keefe["']|"Dee O\\'Keefe"|'Dee O\\'Keefe'""", joined):
            fails.append("campaign_spec: render example does not build a subscriber named Dee O'Keefe")
        if not re.search(r"expect\(.*mustache_template_for.*\)\.to\s+include\(\s*[\"']Dee O&#39;Keefe[\"']\s*\)", joined):
            fails.append("campaign_spec: render example does not expect the escaped 'Dee O&#39;Keefe'")

    slack = "app/services/message_apis/slack/api.rb"
    try:
        stext = open(slack, encoding="utf-8").read()
        if 'user_scope: "channels:history,channels:write,channels:read"' not in stext:
            fails.append("slack plugin: upstream #917 reduced user_scope not applied")
    except FileNotFoundError:
        fails.append("slack plugin missing")

    ra = open("config/initializers/rack_attack.rb", encoding="utf-8").read()
    if not re.search(r'throttle\(\s*"logins/ip",\s*limit:\s*20,\s*period:\s*1\.hour', ra):
        fails.append("rack-attack logins/ip throttle 20/hour missing")
    dv = open("config/initializers/devise.rb", encoding="utf-8").read()
    for flag in ("send_email_changed_notification", "send_password_change_notification"):
        if not re.search(rf"^\s*config\.{flag}\s*=\s*true", dv, re.M):
            fails.append(f"devise {flag} not enabled")
    if "def send_devise_notification" not in open("app/models/agent.rb", encoding="utf-8").read():
        fails.append("Agent#send_devise_notification missing")
    if re.search(r"^\s*use\s+Rack::Attack", open("config.ru", encoding="utf-8").read(), re.M):
        fails.append("config.ru inserts Rack::Attack")
    for env in ("production", "development"):
        text = open(f"config/environments/{env}.rb", encoding="utf-8").read()
        if re.search(r"^\s*Aws::Rails\.add_action_mailer_delivery_method", text, re.M):
            fails.append(f"{env}.rb still calls Aws::Rails.add_action_mailer_delivery_method")

    if fails:
        print("\n".join(fails))
        sys.exit(1)
    print("INTEGRITY PROBE PASS")


main()
