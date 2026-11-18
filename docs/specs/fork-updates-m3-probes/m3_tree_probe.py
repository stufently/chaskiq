"""Probe for fork-updates-m3 (m1 checks, own-files prefix fork-updates-m3): supply-chain and hygiene checks over BASE...HEAD and the tree.

Usage: python3 -I m3_tree_probe.py <BASE_SHA>   (run from the clone root)
Fails on: invisible Unicode (variation selectors U+FE00-FE0F, U+E0100-E01EF, zero-width,
bidi controls, BOM) in added lines or file names; eval/new Function/child_process in
esbuild.config.mjs; any .vscode/ path; self-hosted runners in workflows; an active
skip_client_authentication_for_password_grant; tracked .env files other than .env.example;
foreign branding / malicious-fork markers in added lines; eval( / new Function( added to
JS/TS/JSON; tracked text files still stored with CRLF while git treats them as text;
yarn.lock hosts other than the npm/yarn registries; Gemfile.lock sources other than
rubygems.org and the five GitHub repos that are alive on main (globalize/roadie-rails git
sources must be gone).
"""
import re
import subprocess
import sys


def git(*args):
    return subprocess.run(["git", *args], check=True, capture_output=True).stdout


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: m3_tree_probe.py <BASE_SHA>")
    base = sys.argv[1]
    fails = []
    ranges = [(0xFE00, 0xFE0F), (0xE0100, 0xE01EF), (0x200B, 0x200F), (0x202A, 0x202E), (0x2060, 0x2064), (0xFEFF, 0xFEFF)]
    invisible = re.compile("[" + "".join(f"{chr(a)}-{chr(b)}" for a, b in ranges) + "]")

    diff = git("diff", "--no-color", "-U0", f"{base}...HEAD").decode("utf-8", "replace")
    current = None
    for line in diff.splitlines():
        if line.startswith("+++ "):
            current = line[6:] if line.startswith("+++ b/") else line[4:]
            continue
        if not line.startswith("+") or line.startswith("+++"):
            continue
        added = line[1:]
        if invisible.search(added):
            fails.append(f"invisible Unicode in added line of {current}: {added[:80]!r}")
        own = current is not None and current.startswith("docs/specs/fork-updates-m3")
        if own:
            continue
        low = added.lower()
        for marker in ("wowvendor", "voodoonoir", "kreasialamteknologi", "chaskiq-maintained",
                       "secrets.docker_username }}/chaskiq"):
            if marker in low:
                fails.append(f"foreign branding/marker {marker!r} added in {current}")
        if current and re.search(r"\.(m?js|cjs|jsx|ts|tsx|json)$", current):
            if re.search(r"\beval\s*\(|new\s+Function\s*\(", added):
                fails.append(f"eval/new Function added in {current}: {added[:80]!r}")

    names = git("diff", "--name-only", "-z", f"{base}...HEAD").decode("utf-8", "replace").split("\0")
    for n in filter(None, names):
        if invisible.search(n):
            fails.append(f"invisible Unicode in file name {n!r}")

    tracked = [n for n in git("ls-files", "-z").decode("utf-8", "replace").split("\0") if n]
    if any(n.startswith(".vscode/") or "/.vscode/" in n for n in tracked):
        fails.append(".vscode/ is tracked")
    if any(n.startswith(".vscode/") for n in names):
        fails.append(".vscode/ touched in diff")
    for n in tracked:
        base_name = n.rsplit("/", 1)[-1]
        if re.fullmatch(r"\.env(\..+)?", base_name) and base_name != ".env.example":
            fails.append(f"tracked env file {n}")

    esb = open("esbuild.config.mjs", encoding="utf-8").read()
    if re.search(r"\beval\b|new\s+Function|child_process", esb):
        fails.append("esbuild.config.mjs contains eval/new Function/child_process")

    for n in tracked:
        if n.startswith(".github/workflows/"):
            for ln in open(n, encoding="utf-8", errors="replace"):
                if "self-hosted" in ln and not ln.strip().startswith("#"):
                    fails.append(f"self-hosted runner in {n}")
        if n.startswith("config/") and n.endswith(".rb"):
            for ln in open(n, encoding="utf-8", errors="replace"):
                if re.match(r"\s*skip_client_authentication_for_password_grant\b", ln):
                    fails.append(f"skip_client_authentication_for_password_grant enabled in {n}")

    lock_text = open("yarn.lock", encoding="utf-8").read()
    for block in lock_text.split("\n\n"):
        lines = [b for b in block.splitlines() if b and not b.startswith("#")]
        if not lines or lines[0].startswith(" "):
            continue
        first = lines[0].rstrip(":").split(",")[0].strip().strip('"')
        name = first[: first.rindex("@")] if first.rindex("@") > 0 else first
        version = next((re.match(r'\s+version "([^"]+)"', b).group(1) for b in lines if re.match(r'\s+version "', b)), None)
        resolved = next((re.match(r'\s+resolved "([^"]+)"', b).group(1) for b in lines if re.match(r'\s+resolved "', b)), None)
        if resolved is None:
            continue
        if not resolved.startswith(("https://registry.yarnpkg.com/", "https://registry.npmjs.org/")):
            fails.append(f"yarn.lock resolves from an unexpected host: {resolved[:80]}")
            continue
        short = name.split("/")[-1]
        want = f"/{name}/-/{short}-{version}.tgz"
        if want not in resolved:
            fails.append(f"yarn.lock entry {name}@{version} resolves to a different tarball: {resolved[:100]}")
    allowed_git = {
        "https://github.com/chaskiq/emoji_data.rb.git", "https://github.com/mbleigh/acts-as-taggable-on.git",
        "https://github.com/michelson/nightfury.git", "https://github.com/roo-rb/roo.git",
        "https://github.com/stympy/faker.git",
    }
    for remote in re.findall(r"^  remote: (\S+)$", open("Gemfile.lock", encoding="utf-8").read(), re.M):
        if remote != "https://rubygems.org/" and remote not in allowed_git:
            fails.append(f"Gemfile.lock has an unexpected source: {remote}")

    for row in git("ls-files", "--eol").decode("utf-8", "replace").splitlines():
        meta, _, path = row.partition("\t")
        cols = meta.split()
        if cols and cols[0] in ("i/crlf", "i/mixed") and "attr/-text" not in meta:
            fails.append(f"CRLF file treated as text (would churn under .gitattributes): {path}")

    if fails:
        print("\n".join(fails))
        sys.exit(1)
    print("TREE PROBE PASS")


main()
