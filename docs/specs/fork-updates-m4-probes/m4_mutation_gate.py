"""Mutation gate for fork-updates-m4: the tests written in this milestone must kill these mutants.

Usage (clone root): python3 -I docs/specs/fork-updates-m4-probes/m4_mutation_gate.py [MUTANT_ID ...]
Needs: image chaskiq-test:m1, gems in $HOME/.cache/chaskiq-m1/bundle, postgres:14-alpine,
redis:8.10-alpine, axllent/mailpit:v1.34.0.

The new code of this milestone does not exist at BASE, so most mutants do not edit a fragment:
they APPEND a Ruby override to the end of the file that brings back the BASE behaviour of one
method (`append`), whatever the implementation above it looks like. Two kinds of mutants:
  ("replace", fragment, replacement, count) - fragment must occur exactly `count` times;
  ("append", ruby) - the file must define the method the override replaces (`needs`).
For every target (one rspec file, or a mode of m4_boot_probe.sh) the gate first proves the
target is green on the clean tree. A mutant counts as killed only when the target fails for
the right reason: for rspec, the run had failures, no errors outside examples, and at least one
failed example in the target file whose full description matches the mutant's marker
(case-insensitive); for the boot probe, the expected FAIL line. The original bytes are restored
in `finally` (sha256 re-checked). Exit 0 only when every mutant is killed by every target.
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
BM_SPEC = "spec/services/message_apis/block_manager_spec.rb"
BM = "app/services/message_apis/block_manager.rb"
SLACK = "app/services/message_apis/slack/api.rb"
BOOT = "docs/specs/fork-updates-m4-probes/m4_boot_probe.sh"


def spec(name):
    return f"{HOOKS}/{name}_spec.rb"


def bm_override(body):
    return f"\nclass MessageApis::BlockManager\n{body}\nend\n"


SMTP_FORCE = ("append", "\nRails.application.configure do\n"
              "  s = config.action_mailer.smtp_settings\n"
              "  config.action_mailer.smtp_settings = s.merge(authentication: :login) if s\nend\n", None)


MUTANTS = [
    # id, file, kind-tuple, targets, marker (regex on failed example description / boot FAIL line)
    ("LB1", BM, ("append", bm_override(
        '  def self.get_blocks(serialized_content) = JSON.parse(serialized_content)["content"]'),
        "def self.get_blocks"),
     [BM_SPEC, spec("telegram"), spec("vonage"), spec("message_bird"), spec("telnyx_sms")], r"legacy"),
    ("LB2", BM, ("append", bm_override(
        "  def self.get_blocks(serialized_content)\n"
        "    data = JSON.parse(serialized_content)\n"
        '    data.is_a?(Hash) ? (data["content"] || data["blocks"]) : nil\n'
        "  end"), "def self.get_blocks"),
     [BM_SPEC], r"draft"),
    ("PT1", BM, ("append", bm_override(
        "  def self.plain_text(blocks) = Dante::Utils.extract_plain_text(blocks)"), "def self.plain_text"),
     [BM_SPEC, spec("telegram")], r"paragraph"),
    ("UJ1", BM, ("append", bm_override(
        "  def self.absolute_url(url)\n"
        "    return nil if url.blank?\n"
        '    url.match?(%r{\\Ahttps?://}i) ? url : URI.join(Chaskiq::Config.get("HOST"), url).to_s\n'
        "  end"), "def self.absolute_url"),
     [BM_SPEC, spec("telegram")], r"space"),
    ("SE1", SLACK, ("append",
        "\nmodule MessageApis\n  module Slack\n    class Api\n"
        "      def escape_mrkdwn(text) = text.to_s\n    end\n  end\nend\n", "def escape_mrkdwn"),
     [spec("slack")], r"escape"),
    ("RA9", "config/initializers/rack_attack.rb",
     ("replace", "if Rails.env.production? || Rails.env.staging?", "if Rails.env.production?", 1),
     ["boot:--ra-only"], r"FAIL: staging Rack::Attack store is its own redis store"),
    ("SM1", "config/environments/production.rb", SMTP_FORCE,
     ["boot:--smtp-only"], r"FAIL: production SMTP without SMTP_USERNAME"),
    ("SM2", "config/environments/staging.rb", SMTP_FORCE,
     ["boot:--smtp-only"], r"FAIL: staging SMTP without SMTP_USERNAME"),
    ("SM3", "config/environments/development.rb", SMTP_FORCE,
     ["boot:--smtp-only"], r"FAIL: development SMTP without SMTP_USERNAME"),
]


def sh(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


class Env:
    def __init__(self, root):
        self.root = root
        self.id = f"chqm4m-{hashlib.sha256(root.encode()).hexdigest()[:8]}-{os.getpid()}"
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
        out = f"tmp/m4-mut-{os.getpid()}-{self.n}.json"
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

    def boot(self, mode):
        r = sh(["bash", BOOT, mode], cwd=self.root)
        return {"rc": r.returncode, "tail": (r.stdout + r.stderr)[-600:]}


def run_target(env, target):
    return env.boot(target.split(":", 1)[1]) if target.startswith("boot:") else env.rspec(target)


def green(target, res):
    if target.startswith("boot:"):
        return res["rc"] == 0
    return res.get("rc") == 0 and res.get("total", 0) > 0 and res.get("failures") == 0 and res.get("outside") == 0


def killed(target, res, marker):
    if target.startswith("boot:"):
        hit = res["rc"] != 0 and re.search(marker, res["tail"]) is not None
        return hit, res["tail"].strip().splitlines()[-1:] or [""]
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
            if not t.startswith("boot:") and not os.path.exists(t):
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
