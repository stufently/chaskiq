"""Mutation gate for fork-updates-m3: the tests written in this milestone must kill these mutants.

Usage (clone root): python3 -I docs/specs/fork-updates-m3-probes/m3_mutation_gate.py [MUTANT_ID ...]
Needs: image chaskiq-test:m1, gems in $HOME/.cache/chaskiq-m1/bundle, postgres:14-alpine, redis:5-alpine.

For every target (one rspec file, or the development boot of m3_boot_probe.sh) the gate first
proves the target is green on the clean tree. Then for every mutant: the fragment must occur in
the file exactly `count` times, the mutant is written, the target is run, and the original bytes
are restored in `finally` (sha256 re-checked). A mutant counts as killed only when the target
fails for the right reason: for rspec, the run had failures, no errors outside examples, and at
least one failed example in the target file whose full description matches the mutant's marker.
Exit 0 only when every mutant is killed by every one of its targets. Prints killed/survived per
mutant and target with the first failed example.
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
PLUGIN_SPECS = {
    "telegram": f"{HOOKS}/telegram_spec.rb",
    "message_bird": f"{HOOKS}/message_bird_spec.rb",
    "telnyx_sms": f"{HOOKS}/telnyx_sms_spec.rb",
    "vonage": f"{HOOKS}/vonage_spec.rb",
    "slack": f"{HOOKS}/slack_spec.rb",
}
DEVBOOT = "devboot"

MUTANTS = [
    # id, file, fragment, replacement, count, targets, marker (regex on failed example full description)
    ("PL1", "app/services/message_apis/twilio/api.rb",
     "@conn.request(:authorization, :basic, @api_key, @api_token)",
     "@conn.request(:authorization, :basic, @api_token, @api_key)", 1,
     [f"{HOOKS}/twilio_spec.rb"], r"outgoing"),
    ("PL2", "app/services/message_apis/slack/api.rb",
     'user_scope: "channels:history,channels:write,channels:read"',
     'user_scope: "chat:write,channels:history,channels:write,channels:read"', 1,
     [PLUGIN_SPECS["slack"]], r"user_scope"),
    ("RA6", "config/initializers/rack_attack.rb", "limit: 20, period: 1.hour",
     "limit: 20, period: 1.minute", 1, ["spec/requests/rack_attack_spec.rb"], r"one hour"),
    ("DV3", "config/initializers/devise.rb", "config.send_password_change_notification = true",
     "config.send_password_change_notification = false", 1,
     ["spec/models/agent_notifications_spec.rb"], r"password_change"),
    ("DV4", "config/initializers/devise.rb", "config.send_email_changed_notification = true",
     "config.send_email_changed_notification = false", 1,
     ["spec/models/agent_notifications_spec.rb"], r"email_changed"),
    ("SE4", "config/environments/development.rb", "region: zone", 'region: "us-east-1"', 1,
     [DEVBOOT], None),
    ("TG1", "app/services/message_apis/telegram/api.rb", "https://api.telegram.org/bot",
     "https://mutant.invalid/bot", 1, [PLUGIN_SPECS["telegram"]], r"outgoing"),
    ("MB1", "app/services/message_apis/message_bird/api.rb", "messagebird.com/v1/",
     "mutant.invalid/v1/", 2, [PLUGIN_SPECS["message_bird"]], r"outgoing"),
    ("TX1", "app/services/message_apis/telnyx_sms/api.rb", 'URL = "https://api.telnyx.com/v2/messages"',
     'URL = "https://mutant.invalid/v2/messages"', 1, [PLUGIN_SPECS["telnyx_sms"]], r"outgoing"),
    ("TX2", "app/services/message_apis/telnyx_sms/api.rb", "@api_key = config[:api_key]",
     "@api_key = config[:api_key].to_s.reverse", 1, [PLUGIN_SPECS["telnyx_sms"]], r"outgoing"),
    ("VO1", "app/services/message_apis/vonage/api.rb", "nexmo.com/v0.1/messages",
     "mutant.invalid/v0.1/messages", 2, [PLUGIN_SPECS["vonage"]], r"outgoing"),
    ("SL1", "app/services/message_apis/slack/api.rb", 'path = "/api/chat.postMessage"',
     'path = "/api/chat.mutant"', 1, [PLUGIN_SPECS["slack"]], r"outgoing"),
    ("TXT", "app/services/dante/utils.rb", "text << \"#{node['text']} \"", 'text << ""', 1,
     list(PLUGIN_SPECS.values()), r"outgoing"),
]


def sh(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


class Env:
    def __init__(self, root):
        self.root = root
        self.id = f"chqm3m-{hashlib.sha256(root.encode()).hexdigest()[:8]}-{os.getpid()}"
        self.n = 0

    def up(self):
        sh(["docker", "network", "create", self.id], check=True)
        sh(["docker", "run", "-d", "--name", f"{self.id}-pg", "--network", self.id, "--network-alias", "pg",
            "-e", "POSTGRES_PASSWORD=password", "--tmpfs", "/var/lib/postgresql/data", "postgres:14-alpine"], check=True)
        sh(["docker", "run", "-d", "--name", f"{self.id}-redis", "--network", self.id, "--network-alias", "redis",
            "redis:5-alpine"], check=True)
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
        out = f"tmp/m3-mut-{os.getpid()}-{self.n}.json"
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

    def devboot(self):
        r = sh(["bash", "docs/specs/fork-updates-m3-probes/m3_boot_probe.sh", "--dev-only"], cwd=self.root)
        return {"rc": r.returncode, "tail": (r.stdout + r.stderr)[-300:]}


def run_target(env, target):
    return env.devboot() if target == DEVBOOT else env.rspec(target)


def green(target, res):
    if target == DEVBOOT:
        return res["rc"] == 0
    return res.get("rc") == 0 and res.get("total", 0) > 0 and res.get("failures") == 0 and res.get("outside") == 0


def killed(target, res, marker):
    if target == DEVBOOT:
        hit = res["rc"] != 0 and "FAIL: development SES branch" in res["tail"]
        return hit, res["tail"].strip().splitlines()[-1:] or [""]
    if "error" in res or res.get("outside", 1) != 0 or not res.get("failures"):
        return False, [res.get("error", "no failures / errors outside examples")]
    rel = "./" + target
    hits = [f for f in res["failed"] if f[0] in (target, rel) and re.search(marker, f[1])]
    first = (hits or res["failed"])[0]
    return bool(hits), [f"{first[1]} :: {first[2]}"]


def main():
    root = sh(["git", "rev-parse", "--show-toplevel"], check=True).stdout.strip()
    os.chdir(root)
    os.makedirs("tmp", exist_ok=True)
    wanted = set(sys.argv[1:])
    mutants = [m for m in MUTANTS if not wanted or m[0] in wanted]
    if wanted - {m[0] for m in mutants}:
        sys.exit(f"unknown mutant ids: {sorted(wanted - {m[0] for m in mutants})}")
    for mid, path, frag, _new, count, targets, _marker in mutants:
        text = open(path, encoding="utf-8").read()
        if text.count(frag) != count:
            print(f"{mid}: fragment occurs {text.count(frag)} times in {path}, expected {count}")
            sys.exit(1)
        for t in targets:
            if t != DEVBOOT and not os.path.exists(t):
                print(f"{mid}: target {t} missing")
                sys.exit(1)
    env = Env(root)
    ok = True
    try:
        env.up()
        targets = sorted({t for m in mutants for t in m[5]})
        for t in targets:
            res = run_target(env, t)
            if not green(t, res):
                print(f"CLEAN TARGET NOT GREEN: {t}: {res}")
                sys.exit(1)
            print(f"clean green: {t}")
        for mid, path, frag, new, _count, targets, marker in mutants:
            raw = open(path, "rb").read()
            digest = hashlib.sha256(raw).hexdigest()
            try:
                open(path, "wb").write(raw.replace(frag.encode(), new.encode()))
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
