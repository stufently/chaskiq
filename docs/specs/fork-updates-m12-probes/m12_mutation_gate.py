"""Mutation gate for fork-updates-m12: the tests written in this milestone must kill these mutants.

Usage (clone root): python3 -I docs/specs/fork-updates-m12-probes/m12_mutation_gate.py [MUTANT_ID ...]
Needs: image chaskiq-test:m1, gems in $HOME/.cache/chaskiq-m6/bundle, postgres:14-alpine,
redis:8.10-alpine.

The vendored Nightfury and the health check are new code, so most mutants do not edit a
fragment: they APPEND a Ruby override to the end of the file that brings back the BASE (or a
broken) behaviour of one method, whatever the implementation above it looks like:
  ("replace", fragment, replacement, count) - fragment must occur exactly `count` times;
  ("append", ruby, needs) - the file must contain `needs` (the method the override replaces).
For every target rspec file the gate first proves it is green on the clean tree. A mutant counts
as killed only when the target run had failures, no errors outside examples, and at least one
failed example in the target file whose full description matches the mutant's marker
(case-insensitive). The original bytes are restored in `finally` (sha256 re-checked).
Exit 0 only when every mutant is killed.
"""
import hashlib
import json
import os
import re
import subprocess
import sys

HOME = os.path.expanduser("~")
BUNDLE = os.environ.get("CHASKIQ_M6_BUNDLE", f"{HOME}/.cache/chaskiq-m6/bundle")
IMG = "chaskiq-test:m1"
NF_SPEC = "spec/lib/nightfury_spec.rb"
HC_SPEC = "spec/lib/rack/health_check_spec.rb"
OC_SPEC = "spec/jobs/offline_checker_presence_spec.rb"

MUTANTS = [
    # id, file, kind-tuple, targets, marker (regex on the failed example description)
    ("NF1", "vendor/nightfury/lib/nightfury.rb", ("append",
        "\nmodule Nightfury\n  class << self\n    def redis\n"
        "      @redis ||= Redis::Namespace.new(namespace, redis: Redis.current)\n"
        "    end\n  end\nend\n", "def redis"),
     [NF_SPEC], r"not configured"),
    ("NF2", "config/initializers/nightfury.rb", ("replace",
        'Nightfury.redis.namespace = "nf-#{Rails.env}"',
        'Nightfury.namespace = "nf-#{Rails.env}"', 1),
     [NF_SPEC], r"key prefix"),
    ("NF3", "vendor/nightfury/lib/nightfury/metric/count_time_series.rb", ("append",
        "\nmodule Nightfury\n  module Metric\n    class CountTimeSeries\n"
        "      def incr(step = 1, time = Time.now)\n        set(step, get_step_time(time))\n      end\n"
        "    end\n  end\nend\n", "def incr"),
     [NF_SPEC], r"counts"),
    ("NF4", "vendor/nightfury/lib/nightfury/metric/avg_time_series.rb", ("append",
        "\nmodule Nightfury\n  module Metric\n    class AvgTimeSeries\n      protected\n\n"
        "      def before_set(value, time)\n"
        '        ["1.0,#{value.to_f},#{value.to_f}", time]\n'
        "      end\n    end\n  end\nend\n", "def before_set"),
     [NF_SPEC], r"averages"),
    ("NF5", "vendor/nightfury/lib/nightfury/metric/time_series.rb", ("append",
        "\nmodule Nightfury\n  module Metric\n    class TimeSeries\n"
        "      def get_all\n        return nil unless redis.exists(redis_key)\n\n"
        "        decode_many_data_points(redis.zrange(redis_key, 1, -1, withscores: true))\n"
        "      end\n    end\n  end\nend\n", "def get_all"),
     [NF_SPEC], r"counts|without meta"),
    ("NF6", "vendor/nightfury/lib/nightfury/metric/time_series.rb", ("append",
        "\nmodule Nightfury\n  module Metric\n    class TimeSeries\n"
        "      def get_all\n        return nil unless redis.exists(redis_key)\n\n"
        '        decode_many_data_points(redis.zrangebyscore(redis_key, "(0", "+inf", withscores: true))\n'
        "      end\n    end\n  end\nend\n", "def get_all"),
     [NF_SPEC], r"zero and negative"),
    ("OC1", "app/jobs/offline_checker_job.rb", ("append",
        "\nclass OfflineCheckerJob\n  def perform(user_id, key)\n"
        '    return if Redis.new.pubsub("CHANNELS", key).any?\n\n'
        "    u = AppUser.find_by(id: user_id)\n    return if u.blank?\n    return if u.offline?\n\n"
        "    u&.offline!\n  end\nend\n", "def perform"),
     [OC_SPEC], r"another client"),
    ("OC2", "app/jobs/offline_checker_job.rb", ("append",
        "\nclass OfflineCheckerJob\n  def perform(user_id, key)\n    nil\n  end\nend\n", "def perform"),
     [OC_SPEC], r"no client"),
    ("HC1", "lib/rack/health_check.rb", ("append",
        "\nmodule Rack\n  class HealthCheck\n    protected\n\n"
        "    def redis_connected\n      true\n    end\n  end\nend\n", "def redis_connected"),
     [HC_SPEC], r"503"),
    ("HC2", "lib/rack/health_check.rb", ("append",
        "\nmodule Rack\n  class HealthCheck\n    protected\n\n"
        "    def redis_connected\n      false\n    end\n  end\nend\n", "def redis_connected"),
     [HC_SPEC], r"200"),
]


def sh(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


class Env:
    def __init__(self, root):
        self.root = root
        self.id = f"chqm12m-{hashlib.sha256(root.encode()).hexdigest()[:8]}-{os.getpid()}"
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
        out = f"tmp/m12-mut-{os.getpid()}-{self.n}.json"
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


def green(res):
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
        if not os.path.exists(path):
            print(f"{mid}: {path} missing (required by the spec)")
            sys.exit(1)
        text = open(path, encoding="utf-8").read()
        if kind[0] == "replace" and text.count(kind[1]) != kind[3]:
            print(f"{mid}: fragment occurs {text.count(kind[1])} times in {path}, expected {kind[3]}")
            sys.exit(1)
        if kind[0] == "append" and kind[2] not in text:
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
            res = env.rspec(t)
            if not green(res):
                print(f"CLEAN TARGET NOT GREEN: {t}: {res}")
                sys.exit(1)
            print(f"clean green: {t}")
        for mid, path, kind, targets, marker in mutants:
            raw = open(path, "rb").read()
            digest = hashlib.sha256(raw).hexdigest()
            try:
                mutated = mutate(raw, kind)
                if hashlib.sha256(mutated).hexdigest() == digest:
                    print(f"{mid}: mutation did not change {path}")
                    sys.exit(1)
                open(path, "wb").write(mutated)
                for t in targets:
                    res = env.rspec(t)
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
