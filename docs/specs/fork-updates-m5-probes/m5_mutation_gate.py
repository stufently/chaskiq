"""Mutation gate for fork-updates-m5: the tests written in this milestone must kill these mutants.

Usage (clone root): python3 -I docs/specs/fork-updates-m5-probes/m5_mutation_gate.py [MUTANT_ID ...]
Needs: image chaskiq-test:m1, gems in $HOME/.cache/chaskiq-m1/bundle, postgres:14-alpine,
redis:8.10-alpine.

The new code of this milestone does not exist at BASE, so mutants do not edit a fragment: they
APPEND a Ruby override to the end of the file that brings back BASE-like behaviour of one method
(`append`), whatever the implementation above it looks like; the file must define the overridden
method (`needs`). For every target rspec file the gate first proves it is green on the clean tree.
A mutant counts as killed only when the run had failures, no errors outside examples, and at least
one failed example in the target file whose full description matches the mutant's marker
(case-insensitive). The original bytes are restored in `finally` (sha256 re-checked).
Exit 0 only when every mutant is killed by every target.
"""
import hashlib
import json
import os
import re
import subprocess
import sys

HOME = os.path.expanduser("~")
BUNDLE = os.environ.get("CHASKIQ_M1_BUNDLE", f"{HOME}/.cache/chaskiq-m1/bundle")
IMG = "chaskiq-test:m1"
HOOKS = "spec/controllers/api/v1/hooks"
SD_SPEC = "spec/services/message_apis/safe_download_spec.rb"
BM = "app/services/message_apis/block_manager.rb"
SD = "app/services/message_apis/safe_download.rb"
TG = "app/services/message_apis/telegram/api.rb"
TW = "app/services/message_apis/twitter/api.rb"


def spec(name):
    return f"{HOOKS}/{name}_spec.rb"


def reopen(mod, body):
    return f"\n{mod}\n{body}\nend\n"


SD_FIRST_HOP_ONLY = (
    "  def self.fetch(url, max_bytes: 15 * 1024 * 1024, max_redirects: 3)\n"
    "    uri = URI.parse(url.to_s)\n"
    "    return unless uri.is_a?(URI::HTTP) && uri.hostname.present?\n"
    "    ips = resolve(uri.hostname)\n"
    "    return if ips.empty? || ips.any? { |ip| blocked_ip?(ip) }\n"
    "    (max_redirects + 1).times do\n"
    "      res = Net::HTTP.get_response(uri)\n"
    "      return StringIO.new(res.body.to_s) if res.is_a?(Net::HTTPSuccess)\n"
    "      return unless res.is_a?(Net::HTTPRedirection)\n"
    "      uri = URI.join(uri.to_s, res[\"location\"].to_s)\n"
    "    end\n"
    "    nil\n"
    "  rescue StandardError\n"
    "    nil\n"
    "  end")

SD_UNMAPPED = (
    "  def self.blocked_ip?(ip)\n"
    "    a = IPAddr.new(ip.to_s)\n"
    "    %w[0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.0.0.0/24\n"
    "       192.168.0.0/16 198.18.0.0/15 224.0.0.0/4 240.0.0.0/4 ::/128 ::1/128 fc00::/7 fe80::/10 ff00::/8]\n"
    "      .map { |r| IPAddr.new(r) }.any? { |r| r.family == a.family && r.include?(a) }\n"
    "  rescue IPAddr::Error\n"
    "    true\n"
    "  end")

TW_OPEN_URI = (
    "module MessageApis\n  module Twitter\n    class Api\n"
    "      def upload_media(media, media_category_prefix: \"dm\")\n"
    "        require \"open-uri\"\n"
    "        file = URI.parse(media).open\n"
    "        mime = Marcel::MimeType.for(file)\n"
    "        return chunk_upload(file, mime, \"#{media_category_prefix}_image\") if mime.include?(\"image\")\n"
    "      end\n    end\n  end\nend")

MUTANTS = [
    # id, file, kind-tuple, targets, marker (regex on failed example description)
    ("MB1", BM, ("append", reopen("class MessageApis::BlockManager",
        "  def self.media_blocks(blocks)\n"
        "    Array(blocks).grep(Hash).select { |b| %w[ImageBlock VideoBlock FileBlock AudioRecorderBlock].include?(b[\"type\"]) }.first(1)\n"
        "  end"), "def self.media_blocks"),
     [spec("telegram"), spec("vonage"), spec("message_bird")], r"attachment"),
    ("CP1", TG, ("append", reopen("class MessageApis::Telegram::Api",
        "  def upload_telegram(channel_id, data, method: \"sendPhoto\")\n"
        "    @conn.post(\"#{@url}/#{method}\", data.except(:caption, \"caption\").merge(chat_id: channel_id).to_json)\n"
        "  end"), "def upload_telegram"),
     [spec("telegram")], r"caption"),
    ("SD1", SD, ("append", reopen("class MessageApis::SafeDownload", "  def self.blocked_ip?(_ip) = false"),
                 "def self.blocked_ip?"),
     [SD_SPEC], r"private"),
    ("SD2", SD, ("append", reopen("class MessageApis::SafeDownload", SD_UNMAPPED), "def self.blocked_ip?"),
     [SD_SPEC], r"mapped"),
    ("SD3", SD, ("append", reopen("class MessageApis::SafeDownload", SD_FIRST_HOP_ONLY), "def self.fetch"),
     [SD_SPEC], r"redirect"),
    ("TW1", TW, ("append", "\n" + TW_OPEN_URI + "\n", "def upload_media"),
     [spec("twitter")], r"private"),
]


def sh(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


class Env:
    def __init__(self, root):
        self.root = root
        self.id = f"chqm5m-{hashlib.sha256(root.encode()).hexdigest()[:8]}-{os.getpid()}"
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
        out = f"tmp/m5-mut-{os.getpid()}-{self.n}.json"
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
