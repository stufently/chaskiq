#!/usr/bin/env python3
"""Integrity probe for fork-updates-m8 (config.load_defaults 7.0 -> 8.1).

Usage (from the repo root): python3 -I docs/specs/fork-updates-m8-probes/m8_integrity_probe.py <BASE_SHA>

Checks the working tree against BASE:
  1. config/application.rb has exactly one `config.load_defaults 8.1` and no other load_defaults;
  2. config/initializers/new_framework_defaults_*.rb are gone (the guide's final step);
  3. none of the framework defaults introduced by 7.1, 7.2, 8.0 or 8.1 is overridden anywhere
     in config/ (the milestone takes all of them; see the spec's flag table);
  4. compatibility code that keeps old artifacts valid is byte-identical to BASE:
     config/initializers/rotator.rb (SHA1 rotation for old Active Storage URLs),
     plugin_verifier.rb, cookies_serializer.rb, session_store.rb, devise.rb, rack_attack.rb;
  5. Gemfile and Gemfile.lock are byte-identical to BASE (no gem changes in this milestone);
  6. existing spec files only gained lines (no line removed or changed), no spec/support files,
     spec_helper/rails_helper/.rspec untouched, no skip/xit/pending added.
Prints one line per failure and "M8 INTEGRITY PASS" when everything holds.
"""
import pathlib
import re
import subprocess
import sys

if len(sys.argv) != 2:
    sys.exit("usage: m8_integrity_probe.py <BASE_SHA>")
BASE = sys.argv[1]
ROOT = pathlib.Path(subprocess.run(["git", "rev-parse", "--show-toplevel"], check=True,
                                   capture_output=True, text=True).stdout.strip())
fails = []


def git(*args):
    return subprocess.run(["git", "-C", str(ROOT), *args], check=True, capture_output=True, text=True).stdout


def base_bytes(path):
    r = subprocess.run(["git", "-C", str(ROOT), "show", f"{BASE}:{path}"], capture_output=True)
    return r.stdout if r.returncode == 0 else None


app = (ROOT / "config/application.rb").read_text(encoding="utf-8")
lds = re.findall(r"^\s*config\.load_defaults\s+(\S+)\s*$", app, re.M)
if lds != ["8.1"]:
    fails.append(f"config/application.rb load_defaults lines: {lds!r}, expected exactly ['8.1']")

left = sorted(p.name for p in (ROOT / "config/initializers").glob("new_framework_defaults*.rb"))
if left:
    fails.append(f"new_framework_defaults files still present: {left}")

FLAGS = [
    "add_autoload_paths_to_load_path", "precompile_filter_parameters", "dom_testing_default_html_version",
    "run_commit_callbacks_on_first_saved_instances_in_transaction", "sqlite3_adapter_strict_strings_by_default",
    "query_log_tags_format", "raise_on_assign_to_attr_readonly", "belongs_to_required_validates_foreign_key",
    "before_committed_on_all_records", "default_column_serializer", "support_sha1_for_non_deterministic_encryption",
    "marshalling_format_version", "run_after_transaction_callbacks_in_order_defined", "generate_secure_token_on",
    "debug_exception_log_level", "cache_format_version", "message_serializer",
    "use_message_serializer_for_metadata", "raise_on_invalid_cache_expiration_time", "sanitizer_vendor",
    "yjit", "web_image_content_types", "postgresql_adapter_decode_dates", "validate_migration_timestamps",
    "strict_freshness", "Regexp.timeout", "escape_json_responses", "action_on_path_relative_redirect",
    "raise_on_missing_required_finder_order_columns", "escape_js_separators_in_json", "render_tracker",
    "remove_hidden_field_autocomplete", "key_generator_hash_digest_class", "hash_digest_class",
]
for path in sorted((ROOT / "config").rglob("*.rb")):
    rel = path.relative_to(ROOT).as_posix()
    for no, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        code = line.split("#", 1)[0]
        for flag in FLAGS:
            if re.search(rf"(?<![\w]){re.escape(flag)}\s*(\|\|)?=", code):
                if rel == "config/initializers/rotator.rb" and flag == "hash_digest_class":
                    continue
                fails.append(f"{rel}:{no} overrides framework default {flag}: {line.strip()}")

for rel in ["config/initializers/rotator.rb", "config/initializers/plugin_verifier.rb",
            "config/initializers/cookies_serializer.rb", "config/initializers/session_store.rb",
            "config/initializers/devise.rb", "config/initializers/rack_attack.rb", "Gemfile", "Gemfile.lock"]:
    cur = (ROOT / rel).read_bytes() if (ROOT / rel).exists() else None
    if cur != base_bytes(rel):
        fails.append(f"{rel} differs from BASE (must stay byte-identical)")

changed = [l for l in git("diff", "--name-status", BASE, "--", "spec", ".rspec").splitlines() if l]
for entry in changed:
    status, *paths = entry.split("\t")
    rel = paths[-1]
    if rel in ("spec/spec_helper.rb", "spec/rails_helper.rb", ".rspec") or rel.startswith("spec/support/"):
        fails.append(f"{rel}: must not change ({status})")
        continue
    if status.startswith(("D", "R")):
        fails.append(f"{rel}: spec files must not be deleted or renamed ({status})")
        continue
    if status.startswith("M"):
        diff = git("diff", "-U0", BASE, "--", rel)
        removed = [d for d in diff.splitlines() if d.startswith("-") and not d.startswith("---")]
        if removed:
            fails.append(f"{rel}: existing lines changed or removed ({len(removed)})")
    added = [d[1:] for d in git("diff", "-U0", BASE, "--", rel).splitlines()
             if d.startswith("+") and not d.startswith("+++")]
    for line in added:
        if re.search(r"\b(xit|xdescribe|xcontext|skip|pending)\b|:skip\b", line):
            fails.append(f"{rel}: adds skip/pending: {line.strip()}")

for f in fails:
    print(f"FAIL: {f}")
if fails:
    sys.exit(1)
print("M8 INTEGRITY PASS")
