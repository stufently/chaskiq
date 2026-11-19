"""Probe for fork-updates-m10: dependency/config drift, test-suite integrity, carried invariants, m10 shape.

Usage: python3 -I docs/specs/fork-updates-m10-probes/m10_integrity_probe.py <BASE_SHA>  (clone root)
Fails on:
- Gemfile, Gemfile.lock, package.json, yarn.lock, .rspec, docker-compose.yml, config/, bin/, db/,
  lib/, app/models/, app/jobs/ or app/services/dante/ differ from BASE;
- spec/: a file deleted or renamed; a line removed from an existing spec file (the only exception:
  BASE lines 13-51 of spec/controllers/api/v1/hooks_controller_spec.rb, the m7 block
  "SNS subscription confirmation" with unsigned messages); a new file that is not *_spec.rb, lives
  in spec/support/, or is rails_helper/spec_helper; an added line with skip/pending/x-prefixed
  examples, skip/pending metadata, require "webmock/rspec", RSpec.configure or global net-connect
  switches; MessageApis::SnsMessageVerifier stubbed anywhere but hooks_controller_spec.rb;
- m1..m7 invariants gone (as in m7_integrity_probe.py, m7 shape included);
- m10 shape: no MessageApis::SnsMessageVerifier with VerificationError and the methods of spec
  section 5; certificate not fetched through SafeDownload.fetch with max_redirects: 0,
  max_bytes: exactly 64 KiB and deadline: <= 5 (literal or a constant of the verifier); no
  CertificateUnavailable or SNS_ALLOWED_TOPIC_ARNS; TLS peer verification switched off (VERIFY_NONE /
  verify_mode / verify_hostname = false) in SafeDownload, the verifier or anywhere in app/lib/config; any other HTTP client in the verifier; controller not verifying first
  (before_action :verify_sns_message first, SnsMessageVerifier.verify!), methods used by existing
  specs gone, the unsigned AmazonSnsSubscriptionSucceeded path kept; Aws::SNS used anywhere.
"""
import re
import subprocess
import sys

SKIP_RE = re.compile(r"^\s*(xit|xdescribe|xcontext|xspecify|xexample|xscenario|skip|pending)\b"
                     r"|\b(skip|pending)\s*:|:skip\b|:pending\b|\bskip\s*\(|\bpending\s*\(")
GLOBAL_RE = re.compile(r"webmock/rspec|RSpec\.configure|disable_net_connect!|allow_net_connect!")
OPEN_RE = re.compile(r"URI\.parse\([^)]*\)\.open|URI\.open\b|\bopen-uri\b|(?<![\w.])open\(\s*(url|uri|media)")
STUB_RE = re.compile(r"SnsMessageVerifier\)?\s*\.?\s*(to\s+)?receive|allow(_any_instance_of)?\(\s*MessageApis::SnsMessageVerifier"
                     r"|receive\(:(verify!|authentic\?|digest_for|validate_fields!|canonical_string|signing_certificate"
                     r"|download_certificate|certificate_url\?|decode_signature|topic_allowed\?|certificate_trusted\?"
                     r"|certificate_current\?)")
ALLOWED_REMOVALS = {"spec/controllers/api/v1/hooks_controller_spec.rb": (13, 51)}
VERIFIER_METHODS = ("verify!", "clear_cache!", "digest_for", "validate_fields!",
                    "decode_signature", "topic_allowed?", "canonical_string", "signing_certificate",
                    "download_certificate", "certificate_url?", "certificate_current?")
CONTROLLER_METHODS = ("verify_sns_message", "check_aws_confirmation", "is_notification_message?",
                      "send_subscription_confirmation", "handle_notification", "process_email_notification",
                      "read_mail_file", "find_resources_in_recipient_parts", "find_remitent", "serialize_content")


INT_RE = r"(\d[\d_]*)(?:\s*\*\s*(\d[\d_]*))?"


def int_expr(text):
    m = re.fullmatch(INT_RE, text.strip())
    if not m:
        return None
    value = int(m.group(1).replace("_", ""))
    return value * int(m.group(2).replace("_", "")) if m.group(2) else value


def arg_value(source, args, name):
    """Value of keyword `name` in a call: an integer literal, `a * b`, or a constant assigned so."""
    m = re.search(rf"\b{name}:\s*([A-Z][A-Z0-9_]*|{INT_RE})\s*(,|$)", args)
    if not m:
        return None
    token = m.group(1)
    if token[0].isdigit():
        return int_expr(token)
    const = re.search(rf"^\s*{token}\s*=\s*([^\n#]+)", source, re.M)
    return int_expr(const.group(1).replace(".freeze", "")) if const else None


def git(*args):
    return subprocess.run(["git", *args], check=True, capture_output=True).stdout.decode("utf-8", "replace")


def code_lines(path):
    for n, line in enumerate(open(path, encoding="utf-8", errors="replace"), 1):
        if not line.lstrip().startswith("#"):
            yield n, line


def code(path):
    return "".join(l for _, l in code_lines(path))


def removed_spec_lines(base):
    """BASE line numbers removed from spec files that exist at BASE: {path: [n, ...]}."""
    out, path, old = {}, None, 0
    for line in git("diff", "--no-color", "-U0", base, "--", "spec").splitlines():
        if line.startswith("--- "):
            path = line[6:] if line.startswith("--- a/") else None
        elif line.startswith("@@"):
            old = int(re.match(r"@@ -(\d+)", line).group(1))
        elif line.startswith("-") and path:
            out.setdefault(path, []).append(old)
            old += 1
    return out


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: m10_integrity_probe.py <BASE_SHA>")
    base = sys.argv[1]
    fails = []

    for f in ("Gemfile", "Gemfile.lock", "package.json", "yarn.lock", ".rspec", "docker-compose.yml",
              "config", "bin", "db", "lib", "app/services/dante", "app/models", "app/jobs"):
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
    removed = removed_spec_lines(base)
    for path, lines in sorted(removed.items()):
        allowed = ALLOWED_REMOVALS.get(path)
        bad = [n for n in lines if not allowed or not (allowed[0] <= n <= allowed[1])]
        if bad:
            fails.append(f"lines removed from existing spec file {path} (BASE lines {bad[:5]}...)")
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
            if current != "spec/controllers/api/v1/hooks_controller_spec.rb" and STUB_RE.search(line[1:]):
                fails.append(f"SnsMessageVerifier stubbed in {current}: {line[1:80]!r}")

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

    ver_path = "app/services/message_apis/sns_message_verifier.rb"
    try:
        ver = code(ver_path)
    except OSError:
        ver = ""
        fails.append(f"{ver_path} missing")
    if ver:
        nested = re.search(r"^module MessageApis\b", ver, re.M) and re.search(r"^\s+class SnsMessageVerifier\b", ver, re.M)
        if not (nested or re.search(r"^class MessageApis::SnsMessageVerifier\b", ver, re.M)):
            fails.append(f"{ver_path}: class MessageApis::SnsMessageVerifier missing")
        if subprocess.run(["git", "cat-file", "-e", f"HEAD:{ver_path}"], capture_output=True).returncode != 0:
            fails.append(f"{ver_path}: not committed at HEAD (the path is gitignored: commit it with git add -f)")
        if not re.search(r"class VerificationError\s*<\s*StandardError", ver):
            fails.append(f"{ver_path}: VerificationError < StandardError missing")
        for name in VERIFIER_METHODS:
            if not re.search(rf"^\s*def self\.{re.escape(name)}(\(|\s|$)", ver, re.M):
                fails.append(f"{ver_path}: def self.{name} missing")
        fetch = re.findall(r"MessageApis::SafeDownload\.fetch\(([^)]*)\)", ver)
        if not fetch:
            fails.append(f"{ver_path}: certificate not downloaded through MessageApis::SafeDownload.fetch")
        for args in fetch:
            if not re.search(r"max_redirects:\s*0\b", args):
                fails.append(f"{ver_path}: SafeDownload.fetch without max_redirects: 0 ({args})")
            size = arg_value(ver, args, "max_bytes")
            if size != 64 * 1024:
                fails.append(f"{ver_path}: SafeDownload.fetch max_bytes is {size}, must be 64 * 1024 ({args})")
            limit = arg_value(ver, args, "deadline")
            if limit is None or not 0 < limit <= 5:
                fails.append(f"{ver_path}: SafeDownload.fetch deadline is {limit}, must be 1..5 seconds ({args})")
        for needle, why in (("class CertificateUnavailable", "temporary certificate failures -> 503"),
                            ("SNS_ALLOWED_TOPIC_ARNS", "TopicArn allowlist")):
            if needle not in ver:
                fails.append(f"{ver_path}: {needle} missing ({why})")
        if re.search(r"Net::HTTP|Faraday|HTTP\.|open-uri|URI\.open|Kernel\.open|\bopen\(", ver):
            fails.append(f"{ver_path}: downloads outside SafeDownload")
        for needle in ('"SHA1"', '"SHA256"', "amazonaws"):
            if needle not in ver:
                fails.append(f"{ver_path}: {needle} missing")
    tls_off = re.compile(r"VERIFY_NONE|verify_mode\s*=|verify_hostname\s*=\s*false|ssl_verify|verify_ssl")
    sd_code = code("app/services/message_apis/safe_download.rb")
    if "use_ssl" not in sd_code or tls_off.search(sd_code):
        fails.append("safe_download.rb: TLS peer verification not on its default (use_ssl, no verify_mode override)")
    if ver and tls_off.search(ver):
        fails.append(f"{ver_path}: touches TLS verification")
    for path in git("ls-files", "app", "lib", "config").split():
        if path.endswith(".rb") and re.search(r"VERIFY_NONE", code(path)):
            fails.append(f"{path}: OpenSSL::SSL::VERIFY_NONE in code")
    hooks = code("app/controllers/api/v1/hooks_controller.rb")
    if "MessageApis::SnsMessageVerifier.verify!" not in hooks:
        fails.append("hooks_controller: does not call MessageApis::SnsMessageVerifier.verify!")
    m = [mm.group(1) for mm in re.finditer(r"^\s*before_action\s+:(\w+)", hooks, re.M)]
    if not m or m[0] != "verify_sns_message":
        fails.append(f"hooks_controller: first before_action is not :verify_sns_message ({m})")
    for name in CONTROLLER_METHODS:
        if not re.search(rf"^\s*def {re.escape(name)}(?![\w?!])", hooks, re.M):
            fails.append(f"hooks_controller: def {name} missing (existing specs and mutants use it)")
    if "SnsMessageVerifier::CertificateUnavailable" not in hooks or not re.search(r"service_unavailable|\b503\b", hooks):
        fails.append("hooks_controller: CertificateUnavailable is not answered with 503")
    if "AmazonSnsSubscriptionSucceeded" in hooks:
        fails.append("hooks_controller: unsigned notificationType AmazonSnsSubscriptionSucceeded path still present")
    for path in git("ls-files", "app", "lib", "config").split():
        if path.endswith(".rb") and re.search(r"Aws::SNS|aws-sdk-sns", open(path, encoding="utf-8", errors="replace").read()):
            fails.append(f"{path}: uses Aws::SNS (the gem is not in the bundle)")

    if fails:
        print("\n".join(fails))
        sys.exit(1)
    print("M10 INTEGRITY PROBE PASS")


main()
