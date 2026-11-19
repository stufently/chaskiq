"""Mutation gate for fork-updates-m7: the tests written in this milestone must kill these mutants.

Usage (clone root): python3 -I docs/specs/fork-updates-m7-probes/m7_mutation_gate.py [MUTANT_ID ...]
Needs: image chaskiq-test:m1, gems in $HOME/.cache/chaskiq-m6/bundle (Rails 8 lock) or
$HOME/.cache/chaskiq-m1/bundle (Rails 7.2 lock), postgres:14-alpine, redis:8.10-alpine.

Mutants APPEND a Ruby override to the end of the file that brings back BASE-like behaviour of one
method (`append`); the file must define the overridden method (`needs`). For every target rspec
file the gate first proves it is green on the clean tree. A mutant counts as killed only when the
run had failures, no errors outside examples, and at least one failed example in the target file
whose full description matches the mutant's marker (case-insensitive). The original bytes are
restored in `finally` (sha256 re-checked). Exit 0 only when every mutant is killed by every target.
"""
import hashlib
import json
import os
import re
import subprocess
import sys

HOME = os.path.expanduser("~")


def default_bundle():
    lock = open("Gemfile.lock", encoding="utf-8").read() if os.path.exists("Gemfile.lock") else ""
    if re.search(r"^    rails \(8\.", lock, re.M):
        return f"{HOME}/.cache/chaskiq-m6/bundle"
    return f"{HOME}/.cache/chaskiq-m1/bundle"


BUNDLE = os.environ.get("CHASKIQ_BUNDLE") or default_bundle()
IMG = "chaskiq-test:m1"
HOOKS = "spec/controllers/api/v1/hooks"
TWILIO_SPEC = f"{HOOKS}/twilio_spec.rb"
D360_SPEC = f"{HOOKS}/dialog_360_spec.rb"
BM_SPEC = "spec/services/message_apis/block_manager_spec.rb"
SD_SPEC = "spec/services/message_apis/safe_download_spec.rb"
LINK_SPEC = "spec/services/fetch_link_service_spec.rb"
SNS_SPEC = "spec/controllers/api/v1/hooks_controller_spec.rb"
UPLOAD_SPEC = "spec/graphql/mutations/create_url_upload_spec.rb"
BM = "app/services/message_apis/block_manager.rb"
SD = "app/services/message_apis/safe_download.rb"
HOOKS_CTRL = "app/controllers/api/v1/hooks_controller.rb"
LINK = "app/services/fetch_link_card_service.rb"
UPLOAD = "app/graphql/mutations/create_url_upload.rb"


def reopen(mod, body):
    return f"\n{mod}\n{body}\nend\n"


DELIVER_M5 = (
    "  def self.deliver_attachments(attachments, plain_text, send_text:, captionless: [])\n"
    "    first_success = nil\n"
    "    last_response = nil\n"
    "    caption = plain_text.presence\n"
    "    attachments.each do |media|\n"
    "      attrs = block_data(media)\n"
    "      next unless attrs.is_a?(Hash)\n"
    "      url = absolute_url(attrs[\"url\"])\n"
    "      next unless url\n"
    "      last_response = yield(media[\"type\"], url, caption)\n"
    "      if last_response.success?\n"
    "        first_success ||= last_response\n"
    "        caption = nil\n"
    "      end\n"
    "    end\n"
    "    return first_success if first_success\n"
    "    return send_text.call(plain_text) if plain_text.present?\n"
    "    last_response\n"
    "  end")

LINK_OLD_CALL = (
    "  def call(url)\n"
    "    return if url.nil?\n"
    "    url = url.to_s\n"
    "    client = HTTP.timeout(write: 10, connect: 10, read: 10).follow\n"
    "    res = client.head(url, ssl: { verify_mode: OpenSSL::SSL::VERIFY_NONE })\n"
    "    return if res.code != 200\n"
    "    client.get(url).to_s\n"
    "    nil\n"
    "  rescue StandardError\n"
    "    nil\n"
    "  end")

MUTANTS = [
    # id, file, kind-tuple, targets, marker (regex on failed example description)
    ("MB1", BM, ("append", reopen("class MessageApis::BlockManager",
        "  def self.media_blocks(blocks)\n"
        "    Array(blocks).grep(Hash).select { |b| %w[ImageBlock VideoBlock FileBlock AudioRecorderBlock].include?(b[\"type\"]) }.first(1)\n"
        "  end"), "def self.media_blocks"),
     [TWILIO_SPEC, D360_SPEC], r"attachment"),
    ("CL1", BM, ("append", reopen("class MessageApis::BlockManager", DELIVER_M5), "captionless:"),
     [BM_SPEC, TWILIO_SPEC, D360_SPEC], r"captionless|audio"),
    ("CT1", SD, ("append", reopen("class MessageApis::SafeDownload::Body", "  def mime_type = nil"), "def mime_type"),
     [SD_SPEC, LINK_SPEC], r"content type|opengraph"),
    ("SN1", HOOKS_CTRL, ("append", reopen("class Api::V1::HooksController",
        "  private\n\n"
        "  def send_subscription_confirmation\n"
        "    require \"open-uri\"\n"
        "    url = @request_body[\"SubscribeURL\"]\n"
        "    URI.parse(url).open unless url.to_s.empty?\n"
        "  rescue StandardError\n"
        "    nil\n"
        "  end"), "def send_subscription_confirmation"),
     [SNS_SPEC], r"SubscribeURL"),
    ("LC1", LINK, ("append", reopen("class FetchLinkCardService", LINK_OLD_CALL), "def call"),
     [LINK_SPEC], r"private"),
    ("LC2", LINK, ("append", reopen("class FetchLinkCardService",
        "  def download_image(url)\n"
        "    require \"open-uri\"\n"
        "    URI.parse(url.to_s).open\n"
        "    nil\n"
        "  end"), "def download_image"),
     [LINK_SPEC], r"image"),
    ("UP1", UPLOAD, ("append", reopen("class Mutations::CreateUrlUpload",
        "  def download_to_file(uri)\n"
        "    require \"open-uri\"\n"
        "    URI.parse(uri).open\n"
        "  rescue StandardError\n"
        "    nil\n"
        "  ensure\n"
        "    raise GraphQL::ExecutionError, \"mutant\"\n"
        "  end"), "def download_to_file"),
     [UPLOAD_SPEC], r"private"),
]


def sh(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


class Env:
    def __init__(self, root):
        self.root = root
        self.id = f"chqm7m-{hashlib.sha256(root.encode()).hexdigest()[:8]}-{os.getpid()}"
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
        out = f"tmp/m7-mut-{os.getpid()}-{self.n}.json"
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
