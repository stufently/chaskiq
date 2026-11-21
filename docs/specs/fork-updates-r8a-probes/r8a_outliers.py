#!/usr/bin/env python3
"""COORDINATOR ONLY (BASE move): write the outlier lists of fork-updates-r8a from a RuboCop JSON report.

Usage (from the repo root, after r8a_backlog_probe.sh ran on a tree with r8a_config.patch applied):
  python3 -I docs/specs/fork-updates-r8a-probes/r8a_outliers.py tmp/r8a-backlog/tree.json
Rewrites "outliers" and "cops_keep" of r8a_config.json and outliers.tsv next to this file: every
offense of an R8 cop that RuboCop (without the todo, with the R8 limits) still reports.
"""
import json, pathlib, re, sys

HERE = pathlib.Path(__file__).resolve().parent
CFG_P = HERE / "r8a_config.json"
cfg = json.loads(CFG_P.read_text(encoding="utf-8"))
report = pathlib.Path(sys.argv[1])
raw = report.read_text(encoding="utf-8")
try:
    data = json.loads(raw)
except json.JSONDecodeError as e:
    sys.exit(f"{report}: not JSON ({e}); start: {raw[:200]!r}")
cops = cfg["r8_cops"]
root = report.resolve().parents[2]


def name(path, line, msg, cop):
    m = re.search(r"for `([^`]+)`", msg)
    if m:
        return m.group(1)
    if cop == "Layout/LineLength":
        return "-"
    src = (root / path).read_text(encoding="utf-8").split("\n")[line - 1].strip()
    m = re.match(r"def\s+(self\.)?([\w?!=\[\]<>+-]+)", src)
    if m:
        return (m.group(1) or "") + m.group(2)
    m = re.match(r"(?:class|module)\s+([\w:]+)", src)
    if m:
        return m.group(1)
    return "block: " + src[:60]


rows, outliers = [], {c: {} for c in cops}
for f in data["files"]:
    for o in f["offenses"]:
        c = o["cop_name"]
        if c not in cops:
            continue
        m = re.search(r"([\d.]+)/(\d+)\]", o["message"])
        line = o["location"]["start_line"]
        rows.append((c, f["path"], line, name(f["path"], line, o["message"], c), m.group(1), m.group(2)))
        outliers[c][f["path"]] = outliers[c].get(f["path"], 0) + 1
rows.sort(key=lambda r: (r[0], -float(r[4]), r[1], r[2]))
cfg["outliers"] = {c: dict(sorted(v.items())) for c, v in outliers.items()}
cfg["cops_keep"] = {c: sorted(v) for c, v in outliers.items()}
CFG_P.write_text(json.dumps(cfg, indent=1) + "\n", encoding="utf-8")
with open(HERE / "outliers.tsv", "w", encoding="utf-8") as out:
    out.write("# cop\tfile:line\tmethod/class/block\tvalue\tlimit  (RuboCop without todo, R8 limits)\n")
    for c, p, line, n, v, lim in rows:
        out.write(f"{c}\t{p}:{line}\t{n}\t{v}\t{lim}\n")
print(f"wrote {len(rows)} outliers in {sum(len(v) for v in outliers.values())} cop/file pairs")
