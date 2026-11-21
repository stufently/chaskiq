#!/usr/bin/env python3
"""Source-text inspection ban for spec files (owner rule 2026-11-20).

A test that reads production source as text (`Rails.root.join("app/...").read`, then
`expect(source).to match(...)`) kills a mutant without testing behaviour. Such a test is forbidden
and never counts as a kill.

Usage (from the repo root): python3 -I source_scan.py <BASE_SHA>

Scans every file under spec/ that is added or modified against BASE (committed, staged, unstaged
or untracked): the whole file when it is new, the added lines when it is modified. A line fails when
it matches any rule below. Prints "SOURCE SCAN PASS <n> files" or one "FAIL:" line per match.
"""
import pathlib
import re
import subprocess
import sys

if len(sys.argv) != 2:
    sys.exit("usage: source_scan.py <BASE_SHA>")
BASE = sys.argv[1]
ROOT = pathlib.Path(subprocess.run(["git", "rev-parse", "--show-toplevel"], check=True,
                                   capture_output=True, text=True).stdout.strip())
PROD = r"(app|lib|config|vendor|db)\b"
RULES = [
    ("Rails.root path into production code", re.compile(rf"""Rails\.root\s*\.\s*join\(\s*["']{PROD}""")),
    ("Rails.root path into production code", re.compile(rf"""Rails\.root\s*(/|\+)\s*["']{PROD}""")),
    ("Rails.root path into production code", re.compile(rf"""Rails\.root\.to_s\s*\+\s*["']/?{PROD}""")),
    ("Rails.root path into production code",
     re.compile(rf"""Rails\.(application\.)?root\s*\.\s*(glob|join|children|each_child|find)\(\s*["'](\./)?(\*\*/)?{PROD}""")),
    ("Rails.root path into production code", re.compile(r"""Rails\.application\.root\b""")),
    ("file read of a production path", re.compile(rf"""\bPathname\(\s*["'](\./)?{PROD}""")),
    ("file read of a production path",
     re.compile(rf"""\b(File|IO|Pathname)\s*\.\s*(read|readlines|binread|foreach|open|new|readlink)\b.*["'](\./)?{PROD}/""")),
    ("file read next to the source (__FILE__/__dir__)",
     re.compile(r"""\b(File|IO|Pathname)\s*\.\s*(read|readlines|binread|foreach|open|new)\b.*\b(__FILE__|__dir__)""")),
    ("glob over production code", re.compile(rf"""\bDir\s*(\.\s*(glob|children|entries|each_child)\b|\[).*["'](\./)?{PROD}""")),
    ("source location read", re.compile(r"""\bsource_location\b""")),
    ("method source read",
     re.compile(r"""\b(instance_)?method\(\s*:?[\w"'?!]+\s*\)\s*\.\s*(source|comment)\b|\bmethod_source\b""")),
    ("parser over code",
     re.compile(r"""\bRubyVM::(AbstractSyntaxTree|InstructionSequence)\b|\bRipper\b|\bPrism\s*\.\s*(parse|lex)|\.disasm\b""")),
    ("shell read of code", re.compile(rf"""(`|%x|system\(|Open3)[^\n]*\b(cat|grep|sed|awk|head|tail|git\s+(show|grep))\b""")),
]


def git(*a):
    r = subprocess.run(["git", "-C", str(ROOT), *a], capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(f"FAIL: git {' '.join(a)}: {r.stderr.strip()[:300]}")
    return r.stdout


changed = {}
for line in git("diff", "--name-status", "--no-renames", BASE, "--", "spec").splitlines():
    status, path = line.split("\t", 1)
    if status != "D":
        changed[path] = status
for path in git("ls-files", "--others", "--exclude-standard", "--", "spec").splitlines():
    changed[path] = "A"

fails = []
for path, status in sorted(changed.items()):
    if status == "A":
        lines = list(enumerate((ROOT / path).read_text(encoding="utf-8", errors="replace").splitlines(), 1))
    else:
        lines, n = [], 0
        for d in git("diff", "-U0", "--no-renames", BASE, "--", path).splitlines():
            if m := re.match(r"^@@ -\d+(?:,\d+)? \+(\d+)", d):
                n = int(m.group(1))
            elif d.startswith("+") and not d.startswith("+++"):
                lines.append((n, d[1:]))
                n += 1
    for n, text in lines:
        if text.lstrip().startswith("#"):
            continue
        for why, rx in RULES:
            if rx.search(text):
                fails.append(f"{path}:{n}: {why} - source-text inspection is forbidden and is not a kill: {text.strip()[:120]}")
                break

for f in fails:
    print("FAIL:", f)
if fails:
    sys.exit(1)
print(f"SOURCE SCAN PASS {len(changed)} files")
