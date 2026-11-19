#!/usr/bin/env bash
# Probe for fork-updates-m4: the redis of docker-compose.yml serves Sidekiq 7 and keeps old data.
#   1. docker-compose.yml is valid (docker compose config) and services.redis.image is the
#      pinned redis:8.10-alpine (endoflife.date 2026-11-19: 8.10 is the newest maintained
#      branch, 8.10.3); the redis-server in that image is 8.10.x;
#   2. an RDB written by redis:5-alpine (the old pin) in a named volume loads in the new image
#      with string, list, hash and zset keys intact (sidekiq queues survive the upgrade);
#   3. Sidekiq from Gemfile.lock (7.3, redis-client: needs HELLO, i.e. Redis 6+) enqueues a job
#      and a sidekiq process executes it against that image. On redis 5 this raises
#      "redis-client requires Redis 6+ with HELLO command available".
# Usage (from the repo root): bash docs/specs/fork-updates-m4-probes/m4_compose_probe.sh
set -euo pipefail
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
BUNDLE_DIR=${CHASKIQ_M1_BUNDLE:-$HOME/.cache/chaskiq-m1/bundle}
WANT=redis:8.10-alpine
ID="chqm4c-$(printf '%s' "$ROOT" | sha256sum | cut -c1-8)-$$"
SK=$(mktemp -d "${TMPDIR:-/tmp}/m4-sk.XXXXXX")
cleanup() {
  docker rm -f "$ID-old" "$ID-new" "$ID-redis" >/dev/null 2>&1 || :
  docker volume rm "$ID-data" >/dev/null 2>&1 || :
  docker network rm "$ID" >/dev/null 2>&1 || :
  rm -rf -- "$SK"
}
trap cleanup EXIT
fail() { printf '%s\n' "${2:-}" | tail -20; echo "FAIL: $1"; exit 1; }
wait_redis() {
  for _ in $(seq 1 30); do docker exec "$1" redis-cli ping 2>/dev/null | grep -q PONG && return 0; sleep 1; done
  return 1
}

docker compose -f docker-compose.yml config -q || fail "docker compose config rejects docker-compose.yml"
IMG=$(docker run --rm --user "$(id -u):$(id -g)" -v "$ROOT:/app:ro" -w /app chaskiq-test:m1 \
  ruby -ryaml -e 'puts YAML.load_file("docker-compose.yml", aliases: true).dig("services", "redis", "image")')
[ "$IMG" = "$WANT" ] || fail "services.redis.image is $IMG, expected $WANT"
ver=$(docker run --rm --user "$(id -u):$(id -g)" "$IMG" redis-server --version)
printf '%s\n' "$ver" | grep -Eq ' v=8\.10\.[0-9]+ ' || fail "redis-server in $IMG is not 8.10.x" "$ver"

# Named volume only, no host bind mount: the redis images chown /data themselves.  # docker-root-ok
docker volume create "$ID-data" >/dev/null
docker run -d --name "$ID-old" -v "$ID-data:/data" redis:5-alpine >/dev/null  # docker-root-ok
wait_redis "$ID-old" || fail "redis:5-alpine did not start"
docker exec "$ID-old" redis-cli set m4:str v >/dev/null
docker exec "$ID-old" redis-cli lpush queue:default '{"jid":"m4"}' >/dev/null
docker exec "$ID-old" redis-cli hset m4:hash k v >/dev/null
docker exec "$ID-old" redis-cli zadd schedule 1 m4 >/dev/null
docker exec "$ID-old" redis-cli save >/dev/null
docker rm -f "$ID-old" >/dev/null
docker run -d --name "$ID-new" -v "$ID-data:/data" "$IMG" >/dev/null  # docker-root-ok
wait_redis "$ID-new" || fail "$IMG did not start on the redis:5 volume" "$(docker logs "$ID-new" 2>&1)"
got="$(docker exec "$ID-new" redis-cli get m4:str)|$(docker exec "$ID-new" redis-cli lrange queue:default 0 -1)"
got="$got|$(docker exec "$ID-new" redis-cli hget m4:hash k)|$(docker exec "$ID-new" redis-cli zrange schedule 0 -1)"
[ "$got" = 'v|{"jid":"m4"}|v|m4' ] || fail "redis:5 RDB did not load intact in $IMG: $got" "$(docker logs "$ID-new" 2>&1)"

printf '%s\n' 'require "sidekiq"' 'class M4ProbeJob' '  include Sidekiq::Job' \
  '  def perform(tag) = Sidekiq.redis { |c| c.call("SET", "m4probe:done", tag) }' 'end' > "$SK/job.rb"
docker network create "$ID" >/dev/null
docker run -d --name "$ID-redis" --network "$ID" --network-alias redis "$IMG" >/dev/null
wait_redis "$ID-redis" || fail "$IMG did not start"
SIDEKIQ_SH='bundle exec ruby -r/sk/job.rb -e "M4ProbeJob.perform_async(%q(done))" || exit 1
timeout 60 bundle exec sidekiq -r /sk/job.rb -c 1 >/tmp/sk.log 2>&1 & pid=$!
for _ in $(seq 1 50); do
  v=$(bundle exec ruby -rsidekiq -e "puts %q(VAL=) + Sidekiq.redis { |c| c.call(%q(GET), %q(m4probe:done)) }.to_s")
  if printf "%s\n" "$v" | grep -qx "VAL=done"; then echo "JOB=done"; kill $pid; exit 0; fi
  sleep 1
done
tail -20 /tmp/sk.log; exit 1'
out=$(docker run --rm --network "$ID" --user "$(id -u):$(id -g)" -e HOME=/tmp -e BUNDLE_PATH=/bundle \
  -e BUNDLE_GEMFILE=/app/Gemfile -e REDIS_URL=redis://redis:6379/0 -e SIDEKIQ_SH="$SIDEKIQ_SH" \
  -v "$BUNDLE_DIR:/bundle" -v "$ROOT:/app:ro" -v "$SK:/sk:ro" -w /tmp chaskiq-test:m1 \
  bash -c 'eval "$SIDEKIQ_SH"' 2>&1) || fail "sidekiq did not run the job against $IMG" "$out"
printf '%s\n' "$out" | grep -q '^JOB=done$' || fail "sidekiq job result missing" "$out"
echo "M4 COMPOSE PROBE PASS"
