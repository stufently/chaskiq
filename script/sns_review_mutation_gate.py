"""Check that the SNS review regression specs reject each targeted mutation."""

import json
import pathlib
import subprocess
from typing import NamedTuple


VERIFIER = pathlib.Path("app/services/message_apis/sns_message_verifier.rb")
CONTROLLER = pathlib.Path("app/controllers/api/v1/hooks_controller.rb")
VERIFIER_SPEC = "spec/services/message_apis/sns_message_verifier_spec.rb"
CONTROLLER_SPEC = "spec/controllers/api/v1/hooks_sns_signature_spec.rb"
GATE = "docs/specs/fork-updates-m10-probes/rspec_gate_m10.sh"
RESULT = pathlib.Path("tmp/rspec-m10.json")


class Mutation(NamedTuple):
    name: str
    file: pathlib.Path
    original: str
    replacement: str
    spec: str
    marker: str


MUTATIONS = (
    Mutation(
        "confirmation-allowlist", VERIFIER,
        'return warn_open_topics unless message["Type"] == "SubscriptionConfirmation"',
        "return warn_open_topics if message.key?(\"Type\")",
        CONTROLLER_SPEC, "signed confirmation with an empty allowlist",
    ),
    Mutation(
        "certificate-region", VERIFIER,
        r"[a-z]{2}(-gov|-iso[a-z]?)?-[a-z]+-\d+",
        r"[a-z0-9-]+",
        VERIFIER_SPEC, "region is an S3 or arbitrary label",
    ),
    Mutation(
        "download-lock-identity", VERIFIER,
        "def with_download_lock(url)\n",
        "def with_download_lock(url)\n        url = :shared\n",
        VERIFIER_SPEC, "different exact URLs",
    ),
    Mutation(
        "download-lock-timeout", VERIFIER,
        "LOCK_TIMEOUT = 5",
        "LOCK_TIMEOUT = 30",
        VERIFIER_SPEC, "bounds the lock wait",
    ),
    Mutation(
        "confirmation-retry", CONTROLLER,
        'render(plain: "SNS subscription confirmation unavailable", status: :service_unavailable)',
        "nil",
        CONTROLLER_SPEC, "allowed SubscribeURL fails",
    ),
    Mutation(
        "normalized-cache-key", VERIFIER,
        "URI.parse(url).normalize.to_s",
        "url",
        VERIFIER_SPEC, "normalized SigningCertURL",
    ),
    Mutation(
        "cache-before-verification", VERIFIER,
        "verify.call(certificate)\n          store(url, certificate)",
        "store(url, certificate)\n          verify.call(certificate)",
        VERIFIER_SPEC, "invalid signature would exceed capacity",
    ),
    Mutation(
        "notification-deduplication", CONTROLLER,
        "nx: true, ex: 1.day.to_i",
        "nx: false, ex: 1.day.to_i",
        CONTROLLER_SPEC, "deduplicates a verified Notification",
    ),
    Mutation(
        "notification-expiry", CONTROLLER,
        "nx: true, ex: 1.day.to_i",
        "nx: true",
        CONTROLLER_SPEC, "deduplicates a verified Notification",
    ),
    Mutation(
        "notification-release", CONTROLLER,
        "      release_notification(key, token)\n",
        "",
        CONTROLLER_SPEC, "releases the Notification MessageId",
    ),
    Mutation(
        "request-body-rewind", CONTROLLER,
        "JSON.parse(request.raw_post.to_s)",
        "JSON.parse(request.body.read)",
        CONTROLLER_SPEC, "signed POST without Content-Type",
    ),
)


def run_spec(spec):
    run = subprocess.run(["bash", GATE, "--only", spec], capture_output=True, text=True)
    try:
        data = json.loads(RESULT.read_text())
    except (OSError, ValueError) as error:
        raise RuntimeError(f"{spec} did not produce RSpec results\n{run.stdout}{run.stderr}") from error
    failures = [example["full_description"] for example in data["examples"] if example["status"] == "failed"]
    return run, data["summary"], failures


def test_mutation(mutation):
    source = mutation.file.read_bytes()
    original = mutation.original.encode()
    if source.count(original) != 1:
        raise RuntimeError(f"{mutation.name}: expected exactly one matching source fragment")

    try:
        mutation.file.write_bytes(source.replace(original, mutation.replacement.encode()))
        run, summary, failures = run_spec(mutation.spec)
    finally:
        mutation.file.write_bytes(source)

    if run.returncode == 1 and summary["errors_outside_of_examples_count"] == 0:
        for failure in failures:
            if mutation.marker in failure:
                print(f"{mutation.name} killed by {failure}", flush=True)
                return True
    print(f"{mutation.name} SURVIVED or RSpec did not run the expected example", flush=True)
    print(run.stdout + run.stderr, flush=True)
    return False


def main():
    subprocess.run(["git", "diff", "--quiet", "HEAD", "--", VERIFIER, CONTROLLER], check=True)
    for spec in (CONTROLLER_SPEC, VERIFIER_SPEC):
        run, summary, failures = run_spec(spec)
        if run.returncode != 0 or summary["example_count"] == 0 or failures:
            raise RuntimeError(f"{spec} must pass before mutation\n{run.stdout}{run.stderr}")
        print(f"clean green: {spec}", flush=True)

    killed = [test_mutation(mutation) for mutation in MUTATIONS]
    print(f"SNS review mutations: {sum(killed)}/{len(killed)} killed", flush=True)
    raise SystemExit(0 if all(killed) else 1)


if __name__ == "__main__":
    main()
