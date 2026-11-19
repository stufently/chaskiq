"""Mutation gate for fork-updates-m10: the tests written in this milestone must kill these mutants.

Usage (clone root): python3 -I docs/specs/fork-updates-m10-probes/m10_mutation_gate.py [MUTANT_ID ...]
Needs: image chaskiq-test:m1, gems in $HOME/.cache/chaskiq-m6/bundle, postgres:14-alpine, redis:8.10-alpine.

Mutants APPEND Ruby to the end of the file (reopen the class and override one method); the file
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
VER_SPEC = "spec/services/message_apis/sns_message_verifier_spec.rb"
SIG_SPEC = "spec/controllers/api/v1/hooks_sns_signature_spec.rb"
VER = "app/services/message_apis/sns_message_verifier.rb"
HOOKS_CTRL = "app/controllers/api/v1/hooks_controller.rb"


def reopen(mod, body):
    return f"\n{mod}\n{body}\nend\n"


def fetch_with(**override):
    opts = ", ".join(f"{k}: {v}" for k, v in override.items())
    return ("\nMessageApis::SafeDownload.singleton_class.prepend(Module.new do\n"
            f"  def fetch(url, **opts) = super(url, **opts.merge({opts}))\n"
            "end)\n")


def verifier_prepend(body):
    return f"\nMessageApis::SnsMessageVerifier.singleton_class.prepend(Module.new do\n{body}\nend)\n"


SV = "class MessageApis::SnsMessageVerifier"
REQUIRED_ONLY = (
    "  def self.validate_fields!(message)\n"
    "    keys = %w[Message MessageId Timestamp TopicArn Type Signature SignatureVersion SigningCertURL]\n"
    "    keys += %w[SubscribeURL Token] unless message[\"Type\"] == \"Notification\"\n"
    "    keys.each { |k| raise VerificationError, \"mutant\" unless message[k].is_a?(String) && !message[k].empty? }\n"
    "  end")
MUTANTS = [
    # id, file, kind-tuple, targets, marker (regex on failed example description)
    ("SV1", HOOKS_CTRL, ("append", reopen("class Api::V1::HooksController",
        "  private\n\n"
        "  def verify_sns_message\n"
        "    @request_body = JSON.parse(request.body.read)\n"
        "  rescue JSON::ParserError\n"
        "    render(plain: \"bad request\", status: :bad_request)\n"
        "  end"), "def verify_sns_message"),
     [SIG_SPEC], r"unsigned|tampered"),
    ("HT1", HOOKS_CTRL, ("append", reopen("class Api::V1::HooksController",
        "  private\n\n"
        "  def check_aws_confirmation\n"
        "    return unless request.headers[\"x-amz-sns-message-type\"].to_s.casecmp?(\"SubscriptionConfirmation\")\n\n"
        "    send_subscription_confirmation\n"
        "    render(plain: \"ok\")\n"
        "  end"), "def check_aws_confirmation"),
     [SIG_SPEC], r"header"),
    ("TU1", VER, ("append", verifier_prepend(
        "  def download_certificate(url)\n"
        "    super\n"
        "  rescue MessageApis::SnsMessageVerifier::CertificateUnavailable\n"
        "    raise MessageApis::SnsMessageVerifier::VerificationError, \"mutant\"\n"
        "  end"), "def self.download_certificate"),
     [SIG_SPEC, VER_SPEC], r"temporary|503"),
    ("CS1", VER, ("append", reopen(SV,
        "  def self.canonical_string(message)\n"
        "    keys = %w[Message MessageId SubscribeURL Timestamp Token TopicArn Type]\n"
        "    keys = %w[Message MessageId Timestamp TopicArn Type] if message[\"Type\"] == \"Notification\"\n"
        "    keys.filter_map { |k| \"#{k}\\n#{message[k]}\\n\" unless message[k].nil? }.join\n"
        "  end"), "def self.canonical_string"),
     [VER_SPEC], r"subject"),
    ("NL1", VER, ("append", reopen(SV, REQUIRED_ONLY), "def self.validate_fields!"),
     [VER_SPEC], r"newline"),
    ("RQ1", VER, ("append", reopen(SV,
        "  def self.validate_fields!(message)\n"
        "    message.each { |k, v| raise VerificationError, \"mutant\" if k != \"Message\" && v.is_a?(String) && v.match?(/[\\r\\n]/) }\n"
        "  end"), "def self.validate_fields!"),
     [VER_SPEC], r"required"),
    ("DG1", VER, ("append", reopen(SV,
        "  def self.digest_for(version)\n"
        "    \"SHA256\" if %w[1 2 3].include?(version.to_s)\n"
        "  end"), "def self.digest_for"),
     [VER_SPEC], r"SignatureVersion"),
    ("B64", VER, ("append", reopen(SV,
        "  def self.decode_signature(value)\n"
        "    Base64.decode64(value.to_s)\n"
        "  end"), "def self.decode_signature"),
     [VER_SPEC], r"Base64"),
    ("TA1", VER, ("append", reopen(SV,
        "  def self.topic_allowed?(_arn)\n"
        "    true\n"
        "  end"), "def self.topic_allowed?"),
     [VER_SPEC], r"TopicArn"),
    ("CU1", VER, ("append", reopen(SV,
        "  def self.certificate_url?(url)\n"
        "    URI.parse(url.to_s).host.to_s.end_with?(\"amazonaws.com\", \"amazonaws.com.cn\")\n"
        "  rescue URI::Error\n"
        "    false\n"
        "  end"), "def self.certificate_url?"),
     [VER_SPEC], r"SigningCertURL"),
    ("RD1", VER, ("append", fetch_with(max_redirects=3), "def self.download_certificate"),
     [VER_SPEC], r"redirect"),
    ("SZ1", VER, ("append", fetch_with(max_bytes="70 * 1024"), "def self.download_certificate"),
     [VER_SPEC], r"64 KiB"),
    ("TO1", VER, ("append", fetch_with(deadline=30), "def self.download_certificate"),
     [VER_SPEC], r"5 seconds"),
    ("CA1", VER, ("append", reopen(SV,
        "  def self.signing_certificate(url)\n"
        "    download_certificate(url)\n"
        "  end"), "def self.signing_certificate"),
     [VER_SPEC], r"cache"),
    ("CA2", VER, ("append", reopen(SV,
        "  def self.signing_certificate(url)\n"
        "    @m10_certs ||= {}\n"
        "    raise CertificateUnavailable, \"mutant\" if @m10_certs.key?(url) && @m10_certs[url].nil?\n"
        "    @m10_certs[url] ||= download_certificate(url)\n"
        "  rescue CertificateUnavailable\n"
        "    @m10_certs[url] = nil\n"
        "    raise\n"
        "  end\n"
        "  def self.clear_cache!\n"
        "    @m10_certs = {}\n"
        "  end"), "def self.signing_certificate"),
     [VER_SPEC], r"temporary"),
    ("EX1", VER, ("append", reopen(SV,
        "  def self.certificate_current?(_cert)\n"
        "    true\n"
        "  end"), "def self.certificate_current?"),
     [VER_SPEC], r"not_after"),
]


def sh(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


class Env:
    def __init__(self, root):
        self.root = root
        self.id = f"chqm10m-{hashlib.sha256(root.encode()).hexdigest()[:8]}-{os.getpid()}"
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
        out = f"tmp/m10-mut-{os.getpid()}-{self.n}.json"
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
