#!/usr/bin/env bash
# Probe for fork-updates-m14 (same as m13_compose_volume_probe.sh): an operator's old `bundle` volume from BASE must not hide the
# gems of the rebuilt development image.
#
# docker-compose.yml mounts a named volume over /usr/local/bundle. Docker fills a named volume
# from the image only when the volume is created; afterwards the volume wins. After a gem/ABI
# change (rack 3, Ruby 4) an existing volume keeps the old gems and `bundle exec` fails, so the
# tree must mount a volume with a NEW name (or none) at /usr/local/bundle.
#
# 1. `docker compose config` of BASE ($(git merge-base HEAD @{u}), override M14_BASE) and of the
#    tree: every service that mounted a volume at /usr/local/bundle in BASE mounts in the tree a
#    volume with a different name, or nothing; all such services use the same volume.
# 2. Live: a stand-in image (chaskiq-test:m1 + /usr/local/bundle/IMAGE_MARKER, no build of
#    Dockerfile.development) replaces the app image; an "old" volume <project>_<BASE name> holding
#    STALE_MARKER is created first. `docker compose run --no-deps runner` of BASE sees STALE_MARKER
#    (sanity: the probe can see the failure), the tree sees IMAGE_MARKER and no STALE_MARKER.
# Prints "ok ..." lines and "COMPOSE VOLUME PROBE PASS".
# Usage (from the repo root): bash docs/specs/fork-updates-m14-probes/m14_compose_volume_probe.sh
set -euo pipefail
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
B=${M14_BASE:-$(git merge-base HEAD @{u})}
IMG=${CHASKIQ_TEST_IMAGE:-chaskiq-test:m1}
ID="chqvol-$(printf '%s' "$ROOT" | sha256sum | cut -c1-8)-$$"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/compose-vol.XXXXXX")
STANDIN="$ID-standin:probe"
cleanup() {
  for s in base tree; do
    docker compose -p "$ID-$s" -f "$WORK/$s/docker-compose.yml" -f "$WORK/override.yml" down -v --remove-orphans >/dev/null 2>&1 || :
  done
  docker volume ls -q --filter "name=^$ID" | xargs -r docker volume rm >/dev/null 2>&1 || :
  docker image rm "$STANDIN" >/dev/null 2>&1 || :
  rm -rf -- "$WORK"
}
trap cleanup EXIT
fail() { echo "FAIL: $*"; exit 1; }

mkdir -p "$WORK/base" "$WORK/tree"
git archive "$B" docker-compose.yml .dockerdev | tar -xf - -C "$WORK/base"
cp docker-compose.yml "$WORK/tree/"
[ -d .dockerdev ] && cp -a .dockerdev "$WORK/tree/"

# 1. static: which volume sits on /usr/local/bundle, per service
for s in base tree; do
  docker compose -p "$ID-$s" -f "$WORK/$s/docker-compose.yml" config --format json > "$WORK/$s.json" \
    || fail "docker compose config ($s)"
  jq -r '.services | to_entries[] | . as $e | ($e.value.volumes // [])[]
         | select(.target == "/usr/local/bundle") | "\($e.key) \(.type) \(.source // "-")"' \
    "$WORK/$s.json" | sort > "$WORK/$s.mounts"
done
[ -s "$WORK/base.mounts" ] || fail "BASE mounts nothing at /usr/local/bundle - probe defect"
old=$(awk '{print $3}' "$WORK/base.mounts" | sort -u)
[ "$(printf '%s\n' "$old" | wc -l)" = 1 ] || fail "BASE uses several bundle volumes: $old"
old_name=${old#"$ID-base_"}
if [ -s "$WORK/tree.mounts" ]; then
  new=$(awk '{print $3}' "$WORK/tree.mounts" | sort -u)
  [ "$(printf '%s\n' "$new" | wc -l)" = 1 ] || fail "tree uses several volumes at /usr/local/bundle: $new"
  grep -vq ' volume ' "$WORK/tree.mounts" && fail "tree mounts a non-volume at /usr/local/bundle"
  new_name=${new#"$ID-tree_"}
  [ "$new_name" != "$old_name" ] || fail "tree still mounts the BASE volume '$old_name' at /usr/local/bundle"
  echo "ok tree mounts volume '$new_name' instead of '$old_name' at /usr/local/bundle"
else
  new_name=""
  echo "ok tree mounts nothing at /usr/local/bundle (BASE: '$old_name')"
fi
missing=$(comm -23 <(awk '{print $1}' "$WORK/base.mounts") <(awk '{print $1}' "$WORK/tree.mounts"))
if [ -n "$new_name" ] && [ -n "$missing" ]; then
  fail "services lost the bundle volume: $missing"
fi

# 2. live: old volume with stale gems, stand-in image with fresh gems
printf 'FROM %s\nUSER root\nRUN mkdir -p /usr/local/bundle && touch /usr/local/bundle/IMAGE_MARKER && chmod -R a+rX /usr/local/bundle\n' "$IMG" \
  | docker build -q -t "$STANDIN" - >/dev/null || fail "stand-in image build"
cat > "$WORK/override.yml" <<EOF
services:
  runner:
    image: $STANDIN
    build: !reset null
EOF
for s in base tree; do
  # pre-create nested mount points under the /app bind mount, or docker creates them as root
  jq -r '.services.runner.volumes[]? | select(.target | startswith("/app/")) | .target | ltrimstr("/app/")' \
    "$WORK/$s.json" | while read -r d; do mkdir -p "$WORK/$s/$d"; done
  vol="$ID-${s}_$old_name"
  docker volume create "$vol" >/dev/null
  # mounted over /tmp (1777) the empty volume copies that mode, so no root is needed
  docker run --rm --user "$(id -u):$(id -g)" -v "$vol:/tmp" "$IMG" touch /tmp/STALE_MARKER
  got=$(cd "$WORK/$s" && docker compose -p "$ID-$s" -f docker-compose.yml -f "$WORK/override.yml" \
    run --rm --no-deps -T --user "$(id -u):$(id -g)" --entrypoint "" runner \
    bash -c 'ls -1 /usr/local/bundle | grep -E "^(IMAGE|STALE)_MARKER$" | sort | tr "\n" " "' 2>"$WORK/$s.err") \
    || { tail -20 "$WORK/$s.err"; fail "compose run ($s)"; }
  echo "$s sees: ${got:-nothing}"
  case $s in
    base) [ "${got% }" = "STALE_MARKER" ] || fail "BASE does not see its old volume - probe defect" ;;
    tree) [ "${got% }" = "IMAGE_MARKER" ] || fail "tree sees '${got}' at /usr/local/bundle, want the image gems only" ;;
  esac
done
echo "ok an old '$old_name' volume does not hide the rebuilt image gems"
echo "COMPOSE VOLUME PROBE PASS"
