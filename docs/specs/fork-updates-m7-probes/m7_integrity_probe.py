"""Probe for fork-updates-m7: dependency/config drift, test-suite integrity, carried invariants, m7 shape.

Usage: python3 -I docs/specs/fork-updates-m7-probes/m7_integrity_probe.py <BASE_SHA>  (clone root)
Fails on:
- Gemfile, Gemfile.lock, package.json, yarn.lock, .rspec, docker-compose.yml, config/, bin/, db/,
  lib/, app/models/ or app/services/dante/ differ from BASE;
- spec/: a file deleted or renamed; a line removed from an existing spec file; a new file that is
  not *_spec.rb, lives in spec/support/, or is rails_helper/spec_helper; an added line with
  skip/pending/x-prefixed examples, skip/pending metadata, require "webmock/rspec", RSpec.configure
  or global net-connect switches;
- m1..m5 invariants gone (rack-attack literal, Devise flags, Agent#send_devise_notification,
  config.ru without Rack::Attack, Slack #917 user_scope and #escape_mrkdwn, no
  Aws::Rails.add_action_mailer_delivery_method, BlockManager.absolute_url/media_blocks, no URI.join
  in four plugins, telegram/vonage/message_bird on media_blocks, SafeDownload pinned with ipaddr=,
  twitter through SafeDownload);
- m7 shape: twilio/dialog360 still on `blocks.find` or HOST string concatenation, or not calling
  media_blocks + deliver_attachments; deliver_attachments without `captionless:`; no
  SafeDownload::Body < StringIO with content_type and mime_type; hooks_controller,
  fetch_link_card_service or create_url_upload still on open-uri or not on SafeDownload.fetch;
  SubscribeURL not restricted to amazonaws; link card still fetched with the http gem; any new
  `URI.parse(...).open` / `URI.open` under app/.
"""
import re
import subprocess
import sys

SKIP_RE = re.compile(r"^\s*(xit|xdescribe|xcontext|xspecify|xexample|xscenario|skip|pending)\b"
                     r"|\b(skip|pending)\s*:|:skip\b|:pending\b|\bskip\s*\(|\bpending\s*\(")
GLOBAL_RE = re.compile(r"webmock/rspec|RSpec\.configure|disable_net_connect!|allow_net_connect!")
OPEN_RE = re.compile(r"URI\.parse\([^)]*\)\.open|URI\.open\b|\bopen-uri\b|(?<![\w.])open\(\s*(url|uri|media)")


def git(*args):
    return subprocess.run(["git", *args], check=True, capture_output=True).stdout.decode("utf-8", "replace")


def code_lines(path):
    for n, line in enumerate(open(path, encoding="utf-8", errors="replace"), 1):
        if not line.lstrip().startswith("#"):
            yield n, line


def code(path):
    return "".join(l for _, l in code_lines(path))


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: m7_integrity_probe.py <BASE_SHA>")
    base = sys.argv[1]
    fails = []

    for f in ("Gemfile", "Gemfile.lock", "package.json", "yarn.lock", ".rspec", "docker-compose.yml",
              "config", "bin", "db", "lib", "app/services/dante", "app/models"):
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
    if not re.search(r"^\s*def escape_mrkdwn\b", open(slack, encoding="utf-8").read(), re.M):
        fails.append("MessageApis::Slack::Api#escape_mrkdwn missing")
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

    bm = code("app/services/message_apis/block_manager.rb")
    for name in ("absolute_url", "media_blocks"):
        if not re.search(rf"^\s*def self\.{name}\b", bm, re.M):
            fails.append(f"MessageApis::BlockManager.{name} missing")
    for p in ("telegram", "vonage", "message_bird", "slack"):
        path = f"app/services/message_apis/{p}/api.rb"
        for n, line in code_lines(path):
            if "URI.join" in line:
                fails.append(f"{path}:{n} builds media URLs with URI.join")
    for p in ("telegram", "vonage", "message_bird"):
        path = f"app/services/message_apis/{p}/api.rb"
        text = code(path)
        if re.search(r"blocks\.find\s*\{\s*\|\w+\|\s*%w\[ImageBlock", text):
            fails.append(f"{path}: still picks only the first attachment (blocks.find)")
        if "MessageApis::BlockManager.media_blocks" not in text:
            fails.append(f"{path}: does not use MessageApis::BlockManager.media_blocks")

    sd_path = "app/services/message_apis/safe_download.rb"
    try:
        sd = code(sd_path)
    except OSError:
        sd = None
        fails.append(f"{sd_path} missing")
    if sd is not None:
        for name in ("fetch", "blocked_ip?", "resolve"):
            if not re.search(rf"^\s*def self\.{re.escape(name)}", sd, re.M):
                fails.append(f"MessageApis::SafeDownload.{name} missing")
        if not re.search(r"\.ipaddr\s*=", sd):
            fails.append(f"{sd_path}: connection not pinned with Net::HTTP#ipaddr=")
        if OPEN_RE.search(sd) or re.search(r"\bKernel\.open\b", sd):
            fails.append(f"{sd_path}: uses open-uri / URI.open / Kernel#open")
    tw = code("app/services/message_apis/twitter/api.rb")
    if re.search(r"URI\.parse\([^)]*\)\.open", tw):
        fails.append("twitter plugin still downloads with URI.parse(...).open")
    if 'url.include?("http")' in tw:
        fails.append('twitter plugin still builds the media URL with url.include?("http")')
    if "MessageApis::SafeDownload.fetch" not in tw:
        fails.append("twitter plugin does not download through MessageApis::SafeDownload.fetch")

    for p, needle in (("twilio", r'blocks\.find\s*\{\s*\|\w+\|\s*\w+\["type"\]\s*==\s*"(ImageBlock|FileBlock)"'),
                      ("dialog360", r'blocks\.find\s*\{\s*\|\w+\|\s*\w+\["type"\]\s*==\s*"(ImageBlock|VideoBlock|AudioRecorderBlock|FileBlock)"')):
        path = f"app/services/message_apis/{p}/api.rb"
        text = code(path)
        if re.search(needle, text):
            fails.append(f"{path}: still picks only the first attachment (blocks.find)")
        for call in ("MessageApis::BlockManager.media_blocks", "MessageApis::BlockManager.deliver_attachments"):
            if call not in text:
                fails.append(f"{path}: does not use {call}")
        if 'Chaskiq::Config.get("HOST") +' in text or re.search(r"\bendpoint\s*\+", text):
            fails.append(f"{path}: still builds media URLs by string concatenation with HOST")
    if not re.search(r"^\s*def self\.deliver_attachments\([^)]*captionless:", bm, re.M):
        fails.append("MessageApis::BlockManager.deliver_attachments has no captionless: keyword")
    if sd is not None:
        if not re.search(r"^\s*class Body\s*<\s*StringIO\b", sd, re.M):
            fails.append(f"{sd_path}: MessageApis::SafeDownload::Body < StringIO missing")
        for name in ("mime_type", "content_type"):
            if not re.search(rf"(def {name}\b|attr_reader[^\n]*:{name}\b)", sd):
                fails.append(f"{sd_path}: Body#{name} missing")
    sites = {
        "app/controllers/api/v1/hooks_controller.rb": ("SNS SubscribeURL", True),
        "app/services/fetch_link_card_service.rb": ("link card", True),
        "app/graphql/mutations/create_url_upload.rb": ("URL upload", True),
    }
    for path, (label, _) in sites.items():
        text = code(path)
        if OPEN_RE.search(text) or re.search(r"\bKernel\.open\b", text):
            fails.append(f"{path}: {label} still uses open-uri / URI.open")
        if "MessageApis::SafeDownload.fetch" not in text:
            fails.append(f"{path}: {label} does not download through MessageApis::SafeDownload.fetch")
    if "amazonaws" not in code("app/controllers/api/v1/hooks_controller.rb"):
        fails.append("hooks_controller: SubscribeURL host is not restricted to AWS SNS")
    link = code("app/services/fetch_link_card_service.rb")
    if re.search(r"http_client\.(head|get)\b|HTTP\.[a-z_.()]*\.(head|get)\(", link):
        fails.append("fetch_link_card_service: still fetches pages with the http gem")

    current = None
    for line in git("diff", "--no-color", "-U0", base, "--", "app", "lib").splitlines():
        if line.startswith("+++ "):
            current = line[6:]
            continue
        if line.startswith("+") and not line.startswith("+++") and not line[1:].lstrip().startswith("#"):
            if re.search(r"URI\.parse\([^)]*\)\.open|URI\.open\b", line[1:]):
                fails.append(f"new server-side URI open in {current}: {line[1:80]!r}")

    if fails:
        print("\n".join(fails))
        sys.exit(1)
    print("M7 INTEGRITY PROBE PASS")


main()
