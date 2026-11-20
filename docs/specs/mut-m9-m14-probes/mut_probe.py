#!/usr/bin/env python3
"""Probe for mut-m9-m14 (mutation pass over the tests of milestones m9-m14).

Usage (from the repo root):
  python3 -I docs/specs/mut-m9-m14-probes/mut_probe.py scope <BASE_SHA>
  python3 -I docs/specs/mut-m9-m14-probes/mut_probe.py manifest <BASE_SHA> [--targets FILE] [--sample N]

scope: the only changes against BASE are files under spec/ (added or modified, never deleted, BASE
  git mode kept, regular files); every commit of BASE..HEAD (first parent, no merges) changes only
  such files; no production file (anything outside spec/) differs from BASE in HEAD or in the work
  tree; no untracked file except report.json, report-blocked.md, mut-report.md; no ignored-but-present
  .rspec* or file under app/, lib/, config/, spec/, vendor/nightfury, vendor/php_serialize.
manifest: tmp/mutants/manifest.json (written by the executor, untracked, never committed):
  {"mutants": [{"id": "M001", "milestone": "m10", "file": "<prod path>", "line": 42,
                "description": "...", "status": "killed|killed_new|equivalent",
                "patch": "tmp/mutants/M001.patch", "specs": ["spec/..._spec.rb", ...],
                "test_added": "spec/..._spec.rb" (killed_new only), "reason": "..." (equivalent only)}]}
  Checks:
  1. every mutant: unique id; (milestone, file) is a target of targets.json; the patch file exists,
     touches exactly that file, `git apply --check` succeeds on the tree, and the mutated file differs
     from BASE in its syntax tree (Prism, locations dropped) - no comment/whitespace-only mutants;
     specs exist and are spec files; status is one of the three (a left-over "survived" fails);
  2. per target: at least min_mutants mutants that are not equivalent;
  3. equivalent: a reason of at least 20 characters; at most 20% of a target's mutants;
  4. killed_new: test_added is a spec file changed or added since BASE; it is in specs;
  5. mut-report.md exists and names every mutant id;
  6. re-run: every killed_new mutant and a deterministic sample of N killed ones (default 8; ids
     sorted, evenly spaced): apply the patch, run its specs through `bin/ci-local --only rspec`
     (JSON report), restore the file (`git checkout -- <file>`) and require a clean tree again.
     killed_new: at least one failed example in test_added; killed: failures or errors outside
     examples > 0. Any other outcome fails.
Prints one line per failure and "MUT SCOPE PASS" / "MUT MANIFEST PASS".
"""
import json
import os
import pathlib
import re
import subprocess
import sys

args = sys.argv[1:]
if len(args) < 2 or args[0] not in ("scope", "manifest"):
    sys.exit("usage: mut_probe.py scope|manifest <BASE_SHA> [--targets FILE] [--sample N]")
MODE, BASE = args[0], args[1]
opts = dict(zip(args[2::2], args[3::2]))
ROOT = pathlib.Path(subprocess.run(["git", "rev-parse", "--show-toplevel"], check=True,
                                   capture_output=True, text=True).stdout.strip())
HERE = pathlib.Path(__file__).resolve().parent
UNTRACKED_OK = {"report.json", "report-blocked.md", "mut-report.md"}
CACHE = os.environ.get("CI_LOCAL_CACHE", str(pathlib.Path.home() / ".cache" / "chaskiq-mut-ci"))
fails = []


def git(*a, check=True):
    r = subprocess.run(["git", "-C", str(ROOT), *a], capture_output=True, text=True)
    if check and r.returncode != 0:
        print(f"FAIL: git {' '.join(a)}: {r.stderr.strip()[:300]}")
        sys.exit(1)
    return r


def porcelain():
    return [ln for ln in git("status", "--porcelain").stdout.splitlines()
            if ln[3:] not in UNTRACKED_OK]


def mode_check(raw, where):
    for line in raw.splitlines():
        parts = line.split("\t", 1)
        meta = parts[0].split()
        if len(meta) < 5 or len(parts) < 2:
            continue
        old, new, status, path = meta[0].lstrip(":"), meta[1], meta[4], parts[1]
        if not path.startswith("spec/"):
            fails.append(f"{where}: {path}: outside spec/ (production files are never changed)")
        if status in ("D", "T") or (status != "A" and old != new) or new not in ("100644", "100755"):
            fails.append(f"{where}: {path}: status {status}, mode {old} -> {new} (only added/modified regular files)")


if MODE == "scope":
    mode_check(git("diff", "--raw", "--no-renames", BASE).stdout, "tree")
    if git("diff", "--quiet", BASE, "HEAD", "--", ".", ":(exclude)spec", check=False).returncode != 0:
        fails.append("HEAD differs from BASE outside spec/")
    if git("diff", "--quiet", "HEAD", "--", ".", ":(exclude)spec", check=False).returncode != 0:
        fails.append("work tree differs from HEAD outside spec/ (a mutant left applied?)")
    if git("rev-list", "--merges", f"{BASE}..HEAD").stdout.split():
        fails.append("merge commits in BASE..HEAD")
    for sha in git("rev-list", "--reverse", "--first-parent", f"{BASE}..HEAD").stdout.split():
        mode_check(git("diff-tree", "--raw", "-r", "--no-renames", "--no-commit-id", sha).stdout, f"commit {sha[:12]}")
    untracked = [p for p in git("ls-files", "--others", "--exclude-standard").stdout.splitlines()
                 if p and p not in UNTRACKED_OK]
    if untracked:
        fails.append(f"untracked files: {untracked[:10]}")
    for line in git("status", "--porcelain", "--ignored=matching", "--untracked-files=all").stdout.splitlines():
        p = line[3:]
        if line.startswith("!! ") and (re.match(r"^(\.rspec|(app|lib|config|spec|vendor/nightfury|vendor/php_serialize)/)", p)
                                        or p.endswith(".rspec-local")):
            fails.append(f"{p}: ignored but present (affects the test run)")
    print(f"changed spec files: {len(git('diff', '--name-only', BASE).stdout.split())}")
else:
    targets = json.loads((pathlib.Path(opts.get("--targets", HERE / "targets.json"))).read_text())
    tkey = {(t["milestone"], t["file"]): t for t in targets}
    mpath = ROOT / "tmp" / "mutants" / "manifest.json"
    try:
        mutants = json.loads(mpath.read_text())["mutants"]
    except (OSError, ValueError, KeyError) as e:
        print(f"FAIL: {mpath.relative_to(ROOT)}: {e}")
        sys.exit(1)
    if porcelain():
        print(f"FAIL: work tree not clean before the re-run: {porcelain()[:5]}")
        sys.exit(1)
    changed_specs = set(git("diff", "--name-only", BASE, "--", "spec").stdout.split())
    report_md = (ROOT / "mut-report.md").read_text(encoding="utf-8") if (ROOT / "mut-report.md").exists() else None
    if report_md is None:
        fails.append("mut-report.md missing")
    image = f"chaskiq-ci-local:ruby-{(ROOT / '.ruby-version').read_text().strip()}-ubuntu-26.04"
    uid = f"{os.getuid()}:{os.getgid()}"
    work = ROOT / "tmp" / "mut-probe"
    work.mkdir(parents=True, exist_ok=True)
    ids, per_target, ast_jobs = set(), {}, []
    for m in mutants:
        mid = m.get("id", "?")
        if mid in ids:
            fails.append(f"{mid}: duplicate id")
        ids.add(mid)
        key = (m.get("milestone"), m.get("file"))
        if key not in tkey:
            fails.append(f"{mid}: {key} is not a target of targets.json")
            continue
        st = m.get("status")
        if st not in ("killed", "killed_new", "equivalent"):
            fails.append(f"{mid}: status {st!r} (a survivor needs a test - killed_new - or the blocked contract)")
        per_target.setdefault(key, []).append(m)
        specs = m.get("specs") or []
        if not specs or any(not re.match(r"^spec/.*_spec\.rb$", s) or not (ROOT / s).is_file() for s in specs):
            fails.append(f"{mid}: specs missing or not existing spec files: {specs}")
        patch = ROOT / m.get("patch", "")
        if not patch.is_file():
            fails.append(f"{mid}: patch {m.get('patch')} missing")
            continue
        touched = [ln[6:] for ln in patch.read_text(errors="replace").splitlines() if ln.startswith("+++ b/")]
        if touched != [m["file"]]:
            fails.append(f"{mid}: patch touches {touched}, expected exactly {m['file']}")
            continue
        if git("apply", "--check", str(patch), check=False).returncode != 0:
            fails.append(f"{mid}: patch does not apply to the tree")
            continue
        if m["file"].endswith(".rb"):
            mutated = work / f"{mid}.rb"
            subprocess.run(["git", "-C", str(ROOT), "apply", str(patch)], check=True)
            mutated.write_text((ROOT / m["file"]).read_text(encoding="utf-8"))
            git("checkout", "--", m["file"])
            ast_jobs.append((mid, m["file"], f"tmp/mut-probe/{mid}.rb"))
        if st == "equivalent" and len((m.get("reason") or "").strip()) < 20:
            fails.append(f"{mid}: equivalent without a reason (>= 20 chars)")
        if st == "killed_new":
            ta = m.get("test_added") or ""
            if ta not in changed_specs or ta not in specs:
                fails.append(f"{mid}: test_added {ta!r} is not a spec changed since BASE listed in specs")
        if report_md is not None and not re.search(rf"\b{re.escape(mid)}\b", report_md):
            fails.append(f"{mid}: not in mut-report.md")
    if porcelain():
        fails.append(f"tree not clean after patch checks: {porcelain()[:5]}")
    if ast_jobs:
        (work / "ast.list").write_text("".join(f"{a}\t{b}\t{c}\n" for a, b, c in ast_jobs))
        ruby = ('require "prism"; def pl(n) = n.is_a?(Array) ? n.map { pl(_1) } : (n.is_a?(Prism::Node) ? '
                '[n.class.name] + n.class.fields.reject { |f| f.is_a?(Prism::Reflection::LocationField) || '
                'f.is_a?(Prism::Reflection::OptionalLocationField) }.map { |f| v = n.send(f.name); '
                'f.is_a?(Prism::Reflection::FlagsField) ? (n.send(:flags) & ~1) : pl(v) } : n); '
                'File.readlines(ARGV[0], chomp: true).each { |l| id, a, b = l.split("\\t"); '
                'x, y = [a, b].map { Prism.parse_file(_1) }; '
                'puts "#{id} #{!x.errors.empty? ? "BASEERR" : (y.errors.empty? && pl(x.value) == pl(y.value)) ? "SAMEAST" : "OK"}" }')
        r = subprocess.run(["docker", "run", "--rm", "--user", uid, "-e", "HOME=/tmp", "-v", f"{ROOT}:/app:ro",
                            "-w", "/app", image, "ruby", "-e", ruby, "tmp/mut-probe/ast.list"],
                           capture_output=True, text=True)
        if r.returncode != 0:
            fails.append(f"AST check failed: {r.stderr.strip()[:300]}")
        for ln in r.stdout.splitlines():
            mid, verdict = ln.split()
            if verdict != "OK":
                fails.append(f"{mid}: mutated file has the same syntax tree as BASE ({verdict}): not a real mutant")
    for key, t in tkey.items():
        real = [m for m in per_target.get(key, []) if m.get("status") != "equivalent"]
        eq = [m for m in per_target.get(key, []) if m.get("status") == "equivalent"]
        if len(real) < t["min_mutants"]:
            fails.append(f"{key}: {len(real)} non-equivalent mutants, at least {t['min_mutants']} required")
        if per_target.get(key) and len(eq) * 5 > len(per_target[key]):
            fails.append(f"{key}: {len(eq)} of {len(per_target[key])} mutants marked equivalent (> 20%)")
    counts = {s: sum(1 for m in mutants if m.get("status") == s) for s in ("killed", "killed_new", "equivalent")}
    print(f"mutants: {len(mutants)} {counts}")
    if fails:
        for f in fails:
            print("FAIL:", f)
        sys.exit(1)
    n = int(opts.get("--sample", 8))
    killed = sorted((m for m in mutants if m["status"] == "killed"), key=lambda m: m["id"])
    sample = killed[::max(1, len(killed) // n)][:n] if killed and n > 0 else []
    rerun = [m for m in mutants if m["status"] == "killed_new"] + sample
    for m in rerun:
        out = work / f"{m['id']}.json"
        out.unlink(missing_ok=True)
        subprocess.run(["git", "-C", str(ROOT), "apply", m["patch"]], check=True)
        try:
            r = subprocess.run(["bin/ci-local", "--only", "rspec", "--rspec-args",
                                f"--options .rspec --format json --out tmp/mut-probe/{m['id']}.json " + " ".join(m["specs"])],
                               cwd=ROOT, capture_output=True, text=True, env={**os.environ, "CI_LOCAL_CACHE": CACHE})
        finally:
            git("checkout", "--", m["file"])
        if porcelain():
            fails.append(f"{m['id']}: tree not clean after restoring {m['file']}: {porcelain()[:5]}")
            break
        try:
            rep = json.loads(out.read_text())
        except (OSError, ValueError) as e:
            fails.append(f"{m['id']}: no rspec JSON ({e}); ci-local rc {r.returncode}: {r.stdout[-300:]}")
            continue
        s = rep["summary"]
        failed_files = {e["file_path"].lstrip("./") for e in rep["examples"] if e["status"] == "failed"}
        if m["status"] == "killed_new":
            ok = m["test_added"] in failed_files
            why = f"no failed example in {m['test_added']} (failed in {sorted(failed_files)[:3]})"
        else:
            ok = s["failure_count"] > 0 or s["errors_outside_of_examples_count"] > 0
            why = "no failure"
        print(f"{m['id']} {m['status']} {m['file']}: failures={s['failure_count']} "
              f"outside={s['errors_outside_of_examples_count']} -> {'red' if ok else 'GREEN'}")
        if not ok:
            fails.append(f"{m['id']}: mutant re-applied, specs did not go red as recorded: {why}")

for f in fails:
    print("FAIL:", f)
if fails:
    sys.exit(1)
print(f"MUT {MODE.upper()} PASS")
