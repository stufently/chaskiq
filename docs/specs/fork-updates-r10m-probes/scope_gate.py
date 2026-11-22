"""Check the exact file scope, commit order, and todo deletions for R10m."""

import json
from pathlib import Path
import subprocess
import sys


def git(*args):
    return subprocess.check_output(["git", *args], text=True)


def require(condition, message):
    if not condition:
        sys.exit(message)


base = sys.argv[1]
phase = sys.argv[2]
todo = ".rubocop_todo.yml"
changelog = "CHANGELOG.md"
config = json.loads(Path(__file__).with_name("r10m_config.json").read_text())
targets = config["cops_partial"]
adapters = set().union(*targets.values())
specs = {
    f"spec/services/message_apis/{Path(path).parent.name}_r10m_spec.rb"
    for path in adapters
}
paths = set(git("diff", "--name-only", base, "HEAD").splitlines())
require(git("diff", "HEAD").strip() == "", "Tracked changes are not committed")
require(not git("ls-files", "--others", "--exclude-standard", "--", "app", "lib", "config", "spec"),
        "Untracked application or spec files")
if phase == "baseline":
    require(not paths, f"Expected a fresh clone, got {sorted(paths)}")
    print("R10M BASELINE SCOPE PASS")
    sys.exit()

require(phase == "final", f"Unknown phase: {phase}")
require(paths == adapters | specs | {todo, changelog}, f"Unexpected scope: {sorted(paths)}")
commits = git("rev-list", "--reverse", f"{base}..HEAD").splitlines()
expected_phases = [specs, adapters, {todo}, {changelog}]
require(len(commits) >= len(expected_phases), f"Expected at least four commits, got {len(commits)}")
for commit, expected_paths in zip(commits, expected_phases):
    actual = set(git("diff-tree", "--no-commit-id", "--name-only", "-r", commit).splitlines())
    require(actual == expected_paths, f"Unexpected commit scope {commit}: {sorted(actual)}")
for commit in commits:
    actual = set(git("diff-tree", "--no-commit-id", "--name-only", "-r", commit).splitlines())
    require(actual and actual <= paths, f"Unexpected commit scope {commit}: {sorted(actual)}")
    subject, _, body = git("show", "-s", "--format=%s%n%b", commit).strip().partition("\n")
    require(len(subject) <= 50 and not body.strip(), f"Invalid commit message: {commit}")

removed = set()
expected_lines = []
cop = None
for line in git("show", f"{base}:{todo}").splitlines(keepends=True):
    if line.startswith("Metrics/"):
        cop = line.strip().removesuffix(":")
    path = line.strip().removeprefix("- ").strip("'")
    if path in targets.get(cop, []):
        removed.add((cop, path))
    else:
        expected_lines.append(line)
require(len(removed) == 4, f"Unexpected BASE exclusions: {sorted(removed)}")
require(Path(todo).read_text() == "".join(expected_lines), "Unexpected RuboCop todo change")
added = [
    line[1:] for line in git("diff", "--unified=0", base, "HEAD", "--", *adapters, *specs).splitlines()
    if line.startswith("+") and not line.startswith("+++")
]
require(not any("# rubocop:" in line for line in added), "Added RuboCop directive")
print("R10M SCOPE PASS")
