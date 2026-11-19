"""Mutation gate for fork-updates-m13: the tests written in this milestone must kill these mutants.

Usage (clone root): python3 -I docs/specs/fork-updates-m13-probes/m13_mutation_gate.py [MUTANT_ID ...]
Needs: image chaskiq-test:m1, gems in $HOME/.cache/chaskiq-m13/bundle, postgres:14-alpine,
redis:8.10-alpine.

Mutants APPEND a Ruby override to the end of the file that brings back the BASE (rack 2 style)
or a broken behaviour, whatever the implementation above it looks like:
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
BUNDLE = os.environ.get("CHASKIQ_M13_BUNDLE", f"{HOME}/.cache/chaskiq-m13/bundle")
IMG = os.environ.get("CHASKIQ_TEST_IMAGE", "chaskiq-test:m1")
MM_SPEC = "spec/middleware/maintenance_mode_spec.rb"
FW_SPEC = "spec/lib/rack_forwarded_spec.rb"

MUTANTS = [
    # id, file, kind-tuple, targets, marker (regex on the failed example description)
    ("MM1", "config/middleware/maintenance_mode.rb", ("append",
        "\nmodule Middleware\n  class MaintenanceMode\n    def call(_env)\n"
        '      [200, { "Content-Type" => "text/html" }, [File.read(Rails.root.join("public", "maintenance.html"))]]\n'
        "    end\n  end\nend\n", "def call"),
     [MM_SPEC], r"lint"),
    ("MM2", "config/middleware/maintenance_mode.rb", ("append",
        "\nmodule Middleware\n  class MaintenanceMode\n    def call(_env)\n"
        '      [200, { "content-type" => "text/plain" }, ["maintenance"]]\n'
        "    end\n  end\nend\n", "def call"),
     [MM_SPEC], r"maintenance page"),
    ("FW1", "config/initializers/rack_forwarded.rb", ("append",
        "\nRack::Request.forwarded_priority = %i[forwarded x_forwarded]\n", "forwarded_priority"),
     [FW_SPEC], r"forwarded header"),
    ("FW2", "config/initializers/rack_forwarded.rb", ("append",
        "\nRack::Request.x_forwarded_proto_priority = %i[proto scheme]\n", "x_forwarded_proto_priority"),
     [FW_SPEC], r"scheme"),
]


def sh(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


class Env:
    def __init__(self, root):
        self.root = root
        self.id = f"chqm13m-{hashlib.sha256(root.encode()).hexdigest()[:8]}-{os.getpid()}"
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
        out = f"tmp/m13-mut-{os.getpid()}-{self.n}.json"
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
