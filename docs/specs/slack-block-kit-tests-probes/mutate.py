#!/usr/bin/env python3
"""Mutation gate for slack-block-kit-tests (M1-M4).

Usage (repo root): python3 -I docs/specs/slack-block-kit-tests-probes/mutate.py M1|M2|M3|M4

Applies one exact edit to app/services/message_apis/slack/api.rb, runs the two Slack specs in
Docker through bin/ci-local, always restores the file, and exits 0 only when the mutant is killed:
rspec failed, the failure is in an example (not a load error), and a failing example belongs to the
spec file that must catch this mutant.
"""
import pathlib
import re
import subprocess
import sys

TARGET = pathlib.Path("app/services/message_apis/slack/api.rb")
PAYLOADS = "spec/services/message_apis/slack_block_kit_payloads_spec.rb"
EDGE = "spec/services/message_apis/slack_block_kit_edge_cases_spec.rb"

MUTANTS = {
    "M1": (PAYLOADS, [('BASE_URL = "https://slack.com"', 'BASE_URL = "https://slack.com:8443"')]),
    "M2": (EDGE, [
        ('''        file_data, file = fetch_attachment(slack_file)
        return nil if file_data.nil?
''', '''        file_data, = fetch_attachment(slack_file)
        return nil if file_data.nil?

        file = handle_direct_upload(file_data["url_private_download"], file_data["mimetype"])
'''),
        ('''        file = handle_direct_upload(
          file_data["url_private_download"],
          file_data["mimetype"]
        )
        [file_data, file]
''', '''        [file_data, nil]
'''),
    ]),
    "M3": (EDGE, [(
        "user_options = { username: format_user_name(part.authorable).to_s }",
        "user_options = { username: (format_user_name(part.authorable).to_s unless messageable.is_a?(ConversationPartBlock)) }",
    )]),
    "M4": (EDGE, [(
        "\"\\n <@#{slack_user['id']}>\" if slack_user.present?",
        "\"\\n <@#{slack_user['id']}>\" if slack_user&.dig(\"id\").present?",
    )]),
}


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in MUTANTS:
        sys.exit("usage: mutate.py M1|M2|M3|M4")
    name = sys.argv[1]
    expected_file, edits = MUTANTS[name]
    if subprocess.run(["git", "diff", "--quiet", "--", "app/"]).returncode != 0:
        sys.exit(f"{name}: app/ is not clean before mutating")
    original = TARGET.read_text()
    mutated = original
    for old, new in edits:
        if mutated.count(old) != 1:
            sys.exit(f"{name}: anchor not found exactly once: {old[:60]!r}")
        mutated = mutated.replace(old, new)
    try:
        TARGET.write_text(mutated)
        if subprocess.run(["git", "diff", "--quiet", "--", str(TARGET)]).returncode == 0:
            sys.exit(f"{name}: mutation did not apply")
        run = subprocess.run(
            ["bin/ci-local", "--only", "rspec", "--rspec-args", f"{PAYLOADS} {EDGE}"],
            capture_output=True, text=True)
    finally:
        TARGET.write_text(original)
    out = run.stdout + run.stderr
    failed = re.findall(r"^rspec \./(\S+?):\d+", out, re.M)
    if run.returncode == 0:
        print(out[-3000:])
        sys.exit(f"{name}: SURVIVED (specs green with the mutant)")
    if "error occurred outside of examples" in out or not failed:
        print(out[-3000:])
        sys.exit(f"{name}: INVALID (no failing example; load error or infrastructure failure)")
    if expected_file not in failed:
        print(out[-3000:])
        sys.exit(f"{name}: killed only by {sorted(set(failed))}, expected {expected_file}")
    print(f"{name}: KILLED by {sorted(set(failed))}")


main()
