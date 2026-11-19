"""Mutation gate for fork-updates-m11: the tests written in this milestone must kill these mutants.

Usage (clone root): python3 -I docs/specs/fork-updates-m11-probes/m11_mutation_gate.py [MUTANT_ID ...]
Needs: image chaskiq-test:m1, gems in $HOME/.cache/chaskiq-m6/bundle, postgres:14-alpine, redis:8.10-alpine.

Mutants APPEND Ruby to the end of the file (reopen or prepend and override one method); the file
must define the overridden method (`needs`). For every target rspec file the gate first proves it
is green on the clean tree. A mutant counts as killed only when the run had failures, no errors
outside examples, and at least one failed example in the target file whose full description
matches the mutant's marker (case-insensitive). The original bytes are restored in `finally`
(sha256 re-checked). Exit 0 only when every mutant is killed by every target.
"""
import hashlib
import json
import os
import re
import subprocess
import sys

HOME = os.path.expanduser("~")
BUNDLE = os.environ.get("CHASKIQ_M6_BUNDLE") or f"{HOME}/.cache/chaskiq-m6/bundle"
IMG = "chaskiq-test:m1"
TELNYX_SPEC = "spec/controllers/api/v1/hooks/telnyx_sms_spec.rb"
SDH_SPEC = "spec/services/message_apis/safe_download_headers_spec.rb"
TELNYX = "app/services/message_apis/telnyx_sms/api.rb"
SD = "app/services/message_apis/safe_download.rb"
API = "class MessageApis::TelnyxSms::Api"


def reopen(mod, body):
    return f"\n{mod}\n{body}\nend\n"


def prepend(body):
    return f"\nMessageApis::TelnyxSms::Api.prepend(Module.new do\n{body}\nend)\n"


def sender(media):
    return (
        "  def send_sms_message(channel_id, message, media_urls = [])\n"
        "    phone = resolve_outbound_phone(channel_id)\n"
        "    data = { to: \"+#{channel_id}\" }\n"
        "    data[:text] = message if message.present?\n"
        f"{media}"
        "    @conn.post(URL, data.merge(phone).to_json)\n"
        "  end")


def media_url(cond):
    return reopen(API,
                  "  def media_url?(url)\n"
                  "    uri = URI.parse(url.to_s)\n"
                  "    host = uri.host.to_s.downcase\n"
                  f"    {cond}\n"
                  "  rescue URI::Error\n"
                  "    false\n"
                  "  end")


MEDIA_URL_HTTP = media_url('uri.is_a?(URI::HTTP) && (host == "telnyx.com" || host.end_with?(".telnyx.com"))')
MEDIA_URL_SUFFIX = media_url('uri.is_a?(URI::HTTPS) && host.end_with?("telnyx.com")')
MEDIA_URL_PREFIX = media_url('uri.is_a?(URI::HTTPS) && host.match?(/(\\A|\\.)telnyx\\.com/)')
MEDIA_URL_CO = media_url('uri.is_a?(URI::HTTPS) && host.match?(/(\\A|\\.)telnyx\\.com?\\z/)')


def sd_request(line):
    """SafeDownload mutant: remember the first request's headers and reuse them on later requests."""
    return reopen("class MessageApis::SafeDownload",
                  "  class << self\n"
                  "    alias_method :m11_fetch, :fetch\n"
                  "    alias_method :m11_request, :request\n\n"
                  "    def fetch(url, **opts)\n"
                  "      Thread.current[:m11_headers] = opts[:headers] || {}\n"
                  "      Thread.current[:m11_host] = URI.parse(url).host\n"
                  "      m11_fetch(url, **opts)\n"
                  "    ensure\n"
                  "      Thread.current[:m11_headers] = nil\n"
                  "    end\n\n"
                  "    def request(uri, address, headers, &block)\n"
                  f"{line}\n"
                  "      m11_request(uri, address, headers, &block)\n"
                  "    end\n"
                  "    private :request\n"
                  "  end")


MUTANTS = [
    # id, file, kind-tuple, targets, marker (regex on failed example description)
    ("MU1", TELNYX, ("append", reopen(API, sender("")), "def send_sms_message"),
     [TELNYX_SPEC], r"media_urls"),
    ("HK1", TELNYX, ("append", prepend(
        "  def delivery_hooks(*)\n"
        "    {}\n"
        "  end"), "delivery_hooks(conversation, part)"),
     [TELNYX_SPEC], r"partly sent|message id"),
    ("RS1", TELNYX, ("append", prepend(
        "  def send_message(conversation, part)\n"
        "    response = super\n"
        "    response.respond_to?(:body) ? JSON.parse(response.body) : response\n"
        "  end"), "def send_message"),
     [TELNYX_SPEC], r"message id"),
    ("ER1", TELNYX, ("append", prepend(
        "  def send_message(conversation, part)\n"
        "    conversation.define_singleton_method(:add_message_event) { |*| nil }\n"
        "    super\n"
        "  end"), "def send_message"),
     [TELNYX_SPEC], r"errored"),
    ("IM1", TELNYX, ("append", reopen(API,
        "  def media_block(media, message_id, index)\n"
        "    serialized_block(\"\")\n"
        "  end"), "def media_block"),
     [TELNYX_SPEC], r"inbound MMS"),
    ("IM2", TELNYX, ("append", reopen(API,
        "  def download_media(url)\n"
        "    response = Net::HTTP.get_response(URI(url))\n"
        "    return unless response.is_a?(Net::HTTPSuccess)\n\n"
        "    MessageApis::SafeDownload::Body.new(response.body.to_s, content_type: response[\"content-type\"])\n"
        "  rescue StandardError\n"
        "    nil\n"
        "  end"), "def download_media"),
     [TELNYX_SPEC], r"private"),
    ("IM3", TELNYX, ("append", reopen(API,
        "  def download_media(url)\n"
        "    return unless media_url?(url)\n\n"
        "    MessageApis::SafeDownload.fetch(url, allow_own_host: false,\n"
        "                                         headers: { \"Authorization\" => \"Bearer #{@api_key}\" })\n"
        "  end"), "def download_media"),
     [TELNYX_SPEC], r"oversized"),
    ("AU1", TELNYX, ("append", MEDIA_URL_HTTP, "def media_url?"), [TELNYX_SPEC], r"plain http"),
    ("AU3", TELNYX, ("append", MEDIA_URL_SUFFIX, "def media_url?"), [TELNYX_SPEC], r"lookalike"),
    ("AU4", TELNYX, ("append", MEDIA_URL_PREFIX, "def media_url?"), [TELNYX_SPEC], r"lookalike"),
    ("AU5", TELNYX, ("append", MEDIA_URL_CO, "def media_url?"), [TELNYX_SPEC], r"lookalike"),
    ("AU6", TELNYX, ("append", reopen(API,
        "  def media_url?(_url)\n"
        "    true\n"
        "  end"), "def media_url?"),
     [TELNYX_SPEC], r"foreign host"),
    ("AU2", SD, ("append", sd_request(
        "      headers = Thread.current[:m11_headers] if headers.empty?"), "def self.request(uri, address, headers"),
     [SDH_SPEC, TELNYX_SPEC], r"redirect"),
    ("AU7", SD, ("append", sd_request(
        "      headers = Thread.current[:m11_headers] if headers.empty? && uri.host == Thread.current[:m11_host]"),
        "def self.request(uri, address, headers"),
     [SDH_SPEC, TELNYX_SPEC], r"redirect"),
    ("OH1", SD, ("append",
        "\nMessageApis::SafeDownload.singleton_class.prepend(Module.new do\n"
        "  def fetch(url, **opts) = super(url, **opts.merge(allow_own_host: true))\n"
        "end)\n", "allow_own_host"),
     [SDH_SPEC, TELNYX_SPEC], r"own host"),
    ("SC1", TELNYX, ("append", reopen(API,
        "  def app_channel(id)\n"
        "    find_channel(id)\n"
        "  end"), "def app_channel"),
     [TELNYX_SPEC], r"another app"),
    ("MT1", TELNYX, ("append", reopen(API,
        "  def supported_media?(block)\n"
        "    attachment_url(block).present?\n"
        "  end"), "def supported_media?"),
     [TELNYX_SPEC], r"unsupported"),
    ("RV1", TELNYX, ("append", "\nMessageApis::TelnyxSms::Api.send(:remove_const, :RESUMABLE_DELIVERY)\n",
                      "RESUMABLE_DELIVERY = true"),
     [TELNYX_SPEC], r"message id|retry"),
    ("ST1", TELNYX, ("append", reopen(API,
        "  def process_status(payload)\n"
        "    process_read(payload[:id])\n"
        "  end"), "def process_status"),
     [TELNYX_SPEC], r"delivered"),
    ("ST2", TELNYX, ("append", reopen(API,
        "  def process_status(payload)\n"
        "    process_read(payload[:id]) if Array(payload[:to]).any? { |to| to[:status] == \"delivered\" }\n"
        "  end"), "def process_status"),
     [TELNYX_SPEC], r"failed delivery"),
]


def sh(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


class Env:
    def __init__(self, root):
        self.root = root
        self.id = f"chqm11m-{hashlib.sha256(root.encode()).hexdigest()[:8]}-{os.getpid()}"
        self.n = 0

    def up(self):
        sh(["docker", "network", "create", self.id], check=True)
        sh(["docker", "run", "-d", "--name", f"{self.id}-pg", "--network", self.id, "--network-alias", "pg",
            "-e", "POSTGRES_PASSWORD=password", "--tmpfs", "/var/lib/postgresql/data", "postgres:14-alpine"], check=True)
        sh(["docker", "run", "-d", "--name", f"{self.id}-redis", "--network", self.id, "--network-alias", "redis",
            "redis:8.10-alpine"], check=True)
        for _ in range(60):
            if sh(["docker", "exec", f"{self.id}-pg", "pg_isready", "-U", "postgres", "-h", "127.0.0.1"]).returncode == 0:
                break
            sh(["sleep", "1"])
        r = self.ruby_run("bundle install --quiet && bin/rails db:create db:schema:load >/dev/null")
        if r.returncode != 0:
            sys.exit(f"setup failed: {r.stdout[-2000:]}{r.stderr[-2000:]}")

    def down(self):
        sh(["docker", "rm", "-f", f"{self.id}-pg", f"{self.id}-redis"])
        sh(["docker", "network", "rm", self.id])

    def ruby_run(self, script):
        uid = f"{os.getuid()}:{os.getgid()}"
        return sh(["docker", "run", "--rm", "--network", self.id, "--user", uid,
                   "-e", "HOME=/tmp", "-e", "BUNDLE_PATH=/bundle", "-e", "RAILS_ENV=test",
                   "-e", "DATABASE_URL=postgres://postgres:password@pg:5432/chaskiq_test",
                   "-e", "REDIS_URL=redis://redis:6379/0",
                   "-v", f"{BUNDLE}:/bundle", "-v", f"{self.root}:/app", "-w", "/app", IMG,
                   "bash", "-c", script])

    def rspec(self, target):
        self.n += 1
        out = f"tmp/m11-mut-{os.getpid()}-{self.n}.json"
        if os.path.exists(out):
            os.remove(out)
        r = self.ruby_run(f"bundle exec rspec {target} --format json --out {out}")
        try:
            data = json.load(open(out, encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as e:
            return {"rc": r.returncode, "error": f"no rspec json ({e}); {r.stdout[-400:]}{r.stderr[-400:]}"}
        failed = [e for e in data["examples"] if e["status"] == "failed"]
        return {"rc": r.returncode, "total": data["summary"]["example_count"],
                "failures": data["summary"]["failure_count"],
                "outside": data["summary"]["errors_outside_of_examples_count"],
                "failed": [(e["file_path"], e["full_description"],
                            (e.get("exception") or {}).get("message", "")[:160]) for e in failed]}



def run_target(env, target):
    return env.rspec(target)


def green(target, res):
    return res.get("rc") == 0 and res.get("total", 0) > 0 and res.get("failures") == 0 and res.get("outside") == 0


def killed(target, res, marker):
    if "error" in res or res.get("outside", 1) != 0 or not res.get("failures"):
        return False, [res.get("error", "no failures / errors outside examples")]
    rel = "./" + target
    hits = [f for f in res["failed"] if f[0] in (target, rel) and re.search(marker, f[1], re.I)]
    first = (hits or res["failed"])[0]
    return bool(hits), [f"{first[1]} :: {first[2]}"]


def mutate(raw, kind):
    if kind[0] == "replace":
        return raw.replace(kind[1].encode(), kind[2].encode())
    return raw + kind[1].encode()


def main():
    root = sh(["git", "rev-parse", "--show-toplevel"], check=True).stdout.strip()
    os.chdir(root)
    os.makedirs("tmp", exist_ok=True)
    wanted = set(sys.argv[1:])
    mutants = [m for m in MUTANTS if not wanted or m[0] in wanted]
    if wanted - {m[0] for m in mutants}:
        sys.exit(f"unknown mutant ids: {sorted(wanted - {m[0] for m in mutants})}")
    for mid, path, kind, targets, _marker in mutants:
        text = open(path, encoding="utf-8").read()
        if kind[0] == "replace" and text.count(kind[1]) != kind[3]:
            print(f"{mid}: fragment occurs {text.count(kind[1])} times in {path}, expected {kind[3]}")
            sys.exit(1)
        if kind[0] == "append" and kind[2] and kind[2] not in text:
            print(f"{mid}: {path} does not define `{kind[2]}` (required by the spec)")
            sys.exit(1)
        for t in targets:
            if not os.path.exists(t):
                print(f"{mid}: target {t} missing")
                sys.exit(1)
    env = Env(root)
    ok = True
    try:
        env.up()
        for t in sorted({t for m in mutants for t in m[3]}):
            res = run_target(env, t)
            if not green(t, res):
                print(f"CLEAN TARGET NOT GREEN: {t}: {res}")
                sys.exit(1)
            print(f"clean green: {t}")
        for mid, path, kind, targets, marker in mutants:
            raw = open(path, "rb").read()
            digest = hashlib.sha256(raw).hexdigest()
            try:
                open(path, "wb").write(mutate(raw, kind))
                for t in targets:
                    res = run_target(env, t)
                    k, why = killed(t, res, marker)
                    ok &= k
                    print(f"{mid} {'killed' if k else 'SURVIVED'} by {t}: {why[0][:220]}")
            finally:
                open(path, "wb").write(raw)
                if hashlib.sha256(open(path, "rb").read()).hexdigest() != digest:
                    print(f"{mid}: restore failed for {path}")
                    sys.exit(2)
    finally:
        env.down()
    if not ok:
        print("MUTATION GATE FAIL")
        sys.exit(1)
    print("MUTATION GATE PASS")


main()
