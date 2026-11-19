#!/usr/bin/env python3
"""Mutation gate for fork-updates-m8: the compatibility probe must reject real breakages.

Usage (from the repo root): python3 -I docs/specs/fork-updates-m8-probes/m8_mutation_gate.py [ID ...]

Each mutant inserts one line right after `config.load_defaults 8.1` in config/application.rb
(or replaces one line in an initializer), runs m8_compat_probe.sh and expects it to FAIL on the
named check. The file is restored byte-for-byte in `finally` and its sha256 re-checked.
  KG1  key generator back to SHA1           -> old session cookie no longer decodes
  MS1  message serializer :json (no Marshal) -> old app message verifier token rejected
  SA1  other cookie encryption salt          -> old session cookie no longer decodes
  FV1  plugin frame verifier with JSON       -> new tokens lose symbol keys
The clean tree must pass the probe first.
"""
import hashlib
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(subprocess.run(["git", "rev-parse", "--show-toplevel"], check=True,
                                   capture_output=True, text=True).stdout.strip())
PROBE = ["bash", "docs/specs/fork-updates-m8-probes/m8_compat_probe.sh"]
LD = "    config.load_defaults 8.1\n"
APP = "config/application.rb"
MUTANTS = {
    "KG1": (APP, LD, LD + "    config.active_support.key_generator_hash_digest_class = OpenSSL::Digest::SHA1\n",
            "old session cookie keeps the agent signed in"),
    "MS1": (APP, LD, LD + "    config.active_support.message_serializer = :json\n",
            "old app message verifier token"),
    "SA1": (APP, LD, LD + "    config.action_dispatch.authenticated_encrypted_cookie_salt = \"m8 mutant salt\"\n",
            "old session cookie keeps the agent signed in"),
    "FV1": ("config/initializers/plugin_verifier.rb", 'digest: "SHA256")', 'digest: "SHA256", serializer: JSON)',
            "new messenger login token keeps symbol keys"),
}


def run_probe():
    r = subprocess.run(PROBE, cwd=ROOT, capture_output=True, text=True)
    return r.returncode, r.stdout + r.stderr


def sha(b):
    return hashlib.sha256(b).hexdigest()


ids = sys.argv[1:] or list(MUTANTS)
unknown = [i for i in ids if i not in MUTANTS]
if unknown:
    sys.exit(f"unknown mutants: {unknown}")

rc, out = run_probe()
if rc != 0 or "M8 COMPAT PROBE PASS" not in out:
    print(out[-3000:])
    sys.exit("FAIL: compat probe is not green on the clean tree")
print("clean tree: compat probe green")

survivors = []
for mid in ids:
    rel, old, new, expect = MUTANTS[mid]
    path = ROOT / rel
    orig = path.read_bytes()
    text = orig.decode("utf-8")
    if text.count(old) != 1:
        survivors.append(mid)
        print(f"{mid} ERROR: fragment found {text.count(old)} times in {rel}")
        continue
    try:
        path.write_text(text.replace(old, new), encoding="utf-8")
        if sha(path.read_bytes()) == sha(orig):
            raise RuntimeError("mutation did not change the file")
        rc, out = run_probe()
        failed_line = f"FAILED: " in out and expect in out.split("FAILED: ", 1)[1].splitlines()[0]
        if rc != 0 and failed_line:
            print(f"{mid} killed: probe rejected '{expect}'")
        else:
            survivors.append(mid)
            tail = "\n".join(out.strip().splitlines()[-6:])
            print(f"{mid} SURVIVED (rc={rc}, expected failing check '{expect}')\n{tail}")
    finally:
        path.write_bytes(orig)
        if sha(path.read_bytes()) != sha(orig):
            sys.exit(f"FAIL: {rel} not restored")

if survivors:
    sys.exit(f"MUTATION GATE FAIL: {survivors}")
print("MUTATION GATE PASS")
