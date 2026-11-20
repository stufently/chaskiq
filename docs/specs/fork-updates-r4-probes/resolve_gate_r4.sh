#!/usr/bin/env bash
# Constant-resolution gate for fork-updates-r4 (Style/ClassAndModuleChildren).
#
#   CHASKIQ_R4_CACHE=~/.cache/chaskiq-r4-ci bash resolve_gate_r4.sh <BASE_SHA>
#
# 1. BASE copies of the Ruby files changed since BASE go to tmp/r4-resolve/base, a full BASE
#    checkout (git archive) to tmp/r4-resolve/basetree;
# 2. in the bin/ci-local image, with postgres/redis as in `bin/ci-local --only rspec`:
#    `ruby r4_nest.rb refs` lists every unqualified constant reference of those files with its
#    lexical chain at BASE and in the tree, `ruby r4_nest.rb defs app lib` every constant defined in
#    the source; `bin/rails runner r4_resolve.rb resolve` eager-loads the app (test env) and evaluates
#    each name in both chains: same object (or the same NameError) on both sides, else FAIL - the
#    nested `module A` added A to the lexical scope and the name now resolves to A::Name, or A is a
#    class; the same after a static check of every `<new namespace>::<Name>` defined in the source
#    and again after the plugin load of before_start.rb (reproduced: every plugin file `load`ed);
# 3. `bin/rails runner r4_resolve.rb ancestry` runs twice, in separate processes, in the tree and in
#    the BASE checkout: superclass, ancestors and singleton ancestors (by name) of every class/module
#    the changed files define must be identical.
# Pass = "R4 EAGER LOAD OK" (x3), "R4 RESOLVE PASS <n> references, 2 passes" with n > 0, two
# "R4 ANCESTRY DUMP <n> constants" with the same n > 0 and identical dumps.
set -euo pipefail
BASE=${1:?usage: resolve_gate_r4.sh <BASE_SHA>}
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
CACHE=${CHASKIQ_R4_CACHE:-$HOME/.cache/chaskiq-r4-ci}
IMG="chaskiq-ci-local:ruby-$(tr -d '[:space:]' < .ruby-version)-ubuntu-26.04"
docker image inspect "$IMG" >/dev/null 2>&1 || { echo "FAIL: image $IMG missing (built by bin/ci-local)"; exit 1; }
W=tmp/r4-resolve
rm -rf "$W"
mkdir -p "$W/base" vendor/bundle "$CACHE/bundle-ubuntu-26.04"
git diff --name-only --diff-filter=M "$BASE" -- '*.rb' > "$W/list"
[ -s "$W/list" ] || { echo "FAIL: no Ruby file changed since BASE"; exit 1; }
while IFS= read -r f; do
  mkdir -p "$W/base/$(dirname "$f")"
  git show "$BASE:$f" > "$W/base/$f"
done < "$W/list"
mkdir -p "$W/basetree"
git archive "$BASE" | tar -x -C "$W/basetree"
P=${HERE#"$ROOT"/}
ID="r4resolve-$$-$(date +%s)"
cleanup() { docker rm -f "$ID-pg" "$ID-redis" >/dev/null 2>&1 || :; docker network rm "$ID" >/dev/null 2>&1 || :; }
trap cleanup EXIT INT TERM
docker network create "$ID" >/dev/null
docker run -d --name "$ID-pg" --network "$ID" --network-alias pg -e POSTGRES_PASSWORD=postgres \
  --tmpfs /var/lib/postgresql/data postgres:14-alpine >/dev/null
docker run -d --name "$ID-redis" --network "$ID" --network-alias redis redis:8.10-alpine >/dev/null
ready=""
for _ in $(seq 1 60); do
  if docker exec "$ID-pg" pg_isready -U postgres -h 127.0.0.1 >/dev/null 2>&1; then ready=1; break; fi
  sleep 1
done
[ -n "$ready" ] || { echo "FAIL: postgres did not become ready"; exit 1; }
rc=0
docker run --rm --init --user "$(id -u):$(id -g)" --network "$ID" \
  -e HOME=/tmp -e BUNDLE_PATH=/app/vendor/bundle -e BUNDLE_FROZEN=true \
  -e BUNDLE_BUILD__SCOUT_APM="--with-cflags=-std=gnu17" -e RAILS_ENV=test \
  -e DATABASE_URL=postgres://postgres:postgres@pg:5432/test -e REDIS_URL=redis://redis:6379/0 -e P="$P" \
  -v "$ROOT:/app" -v "$CACHE/bundle-ubuntu-26.04:/app/vendor/bundle" -w /app "$IMG" bash -c '
    set -e
    bundle install --quiet
    bin/rails db:prepare >/dev/null
    ruby "$P/r4_nest.rb" refs tmp/r4-resolve/base . tmp/r4-resolve/list > tmp/r4-resolve/refs.json
    ruby "$P/r4_nest.rb" defs app lib > tmp/r4-resolve/defs.json
    bin/rails runner "$P/r4_resolve.rb" resolve tmp/r4-resolve/refs.json tmp/r4-resolve/defs.json
    bin/rails runner "$P/r4_resolve.rb" ancestry tmp/r4-resolve/refs.json tmp/r4-resolve/anc-tree.json
    cd tmp/r4-resolve/basetree
    BUNDLE_GEMFILE=$PWD/Gemfile bin/rails runner "/app/$P/r4_resolve.rb" ancestry \
      /app/tmp/r4-resolve/refs.json /app/tmp/r4-resolve/anc-base.json' > "$W/out.txt" 2>&1 || rc=$?
grep -E 'R4 |FAIL' "$W/out.txt" | head -40 || :
[ "$rc" = 0 ] || { echo "FAIL: run exited $rc"; tail -20 "$W/out.txt"; exit 1; }
[ "$(grep -cx 'R4 EAGER LOAD OK' "$W/out.txt")" = 3 ] || { echo "FAIL: eager load did not finish 3 times"; exit 1; }
grep -qE '^R4 RESOLVE PASS [1-9][0-9]* references, 2 passes$' "$W/out.txt" || { echo "FAIL: no resolve verdict"; exit 1; }
dumps=$({ grep -E '^R4 ANCESTRY DUMP [1-9][0-9]* constants$' "$W/out.txt" || :; } | sort -u | wc -l)
[ "$(grep -cE '^R4 ANCESTRY DUMP [1-9][0-9]* constants$' "$W/out.txt")" = 2 ] && [ "$dumps" = 1 ] \
  || { echo "FAIL: ancestry dumps missing or of different size"; exit 1; }
jq -S . "$W/anc-base.json" > "$W/anc-base.s"
jq -S . "$W/anc-tree.json" > "$W/anc-tree.s"
if ! cmp -s "$W/anc-base.s" "$W/anc-tree.s"; then
  echo "FAIL: superclass/ancestors differ between BASE and the tree (- BASE, + tree):"
  diff "$W/anc-base.s" "$W/anc-tree.s" | head -20 || :
  exit 1
fi
echo "R4 RESOLVE GATE PASS"
