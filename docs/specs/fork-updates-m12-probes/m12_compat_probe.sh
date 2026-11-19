#!/usr/bin/env bash
# Probe for fork-updates-m12: the vendored Nightfury and the Redis.current replacements read and
# write exactly what a live installation has in Redis.
#
# 1. BASE = $(git merge-base HEAD @{u}) (override: M12_BASE) is exported with `git archive` and
#    must still use the nightfury git gem; the current tracked tree must not.
# 2. One throwaway postgres + redis. BASE boots in production (rails runner) and writes metrics
#    through AppIdentity (count series on two days, an average series, a second count series) and
#    TwilioPhone::Store data (Kredis), then records the raw keys under nf-production:* and what
#    it reads back.
# 3. The tree boots in production against the same redis and must:
#    - read the same values (get_range, get_exact, average) and see the same raw keys (reading must
#      not create or rename keys; the key prefix stays nf-production:);
#    - return every data point from get_all (BASE drops the oldest one, see the spec);
#    - read TwilioPhone::Store.get_values equal to BASE; with a non-empty Kredis.namespace,
#      get_values returns exactly what Store.set_data / Kredis.hash wrote (key m12ns:/twilio_phone/...);
#    - all of it lives in DB 3 of REDIS_URL (redis://redis:6379/3), nothing in DB 0;
#    - answer Rack::HealthCheck with 200 (redis up) and, in a second boot with an unreachable
#      REDIS_URL, with 503;
#    - add one visit; BASE, booted again, must read the new value from the same key;
#    - staging: TwilioPhone::Store writes and reads through Kredis (BASE has no staging entry in
#      config/redis/shared.yml and raises there);
#    - test env: POST /__e2e__/command (cypress-on-rails eval) answers 201 and the helper
#      spec/cypress/e2e_helper.rb loads without a deprecation line.
# Prints one "ok <name>" line per check and "M12 COMPAT PROBE PASS" at the end.
# Usage (from the repo root): bash docs/specs/fork-updates-m12-probes/m12_compat_probe.sh
set -euo pipefail
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
B=${M12_BASE:-$(git merge-base HEAD @{u})}
BUNDLE_DIR=${CHASKIQ_M6_BUNDLE:-$HOME/.cache/chaskiq-m6/bundle}
IMG=chaskiq-test:m1
KEY=$(printf 'c%.0s' $(seq 64))
ID="chqm12c-$(printf '%s' "$ROOT" | sha256sum | cut -c1-8)-$$"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/m12-compat.XXXXXX")
cleanup() {
  docker rm -f "$ID-pg" "$ID-redis" >/dev/null 2>&1 || :
  docker network rm "$ID" >/dev/null 2>&1 || :
  rm -rf -- "$WORK"
}
trap cleanup EXIT
fail() { echo "FAIL: $*"; exit 1; }

mkdir -p "$WORK/base" "$WORK/tree" "$WORK/out"
git archive "$B" | tar -xf - -C "$WORK/base"
git ls-files -z | tar --null -T - -cf - | tar -xf - -C "$WORK/tree"
grep -q 'michelson/nightfury' "$WORK/base/Gemfile" || fail "BASE $B does not use the nightfury git gem (wrong merge-base?)"
grep -q 'nightfury' "$WORK/tree/Gemfile" && fail "tree Gemfile still references nightfury"

docker network create "$ID" >/dev/null
docker run -d --name "$ID-pg" --network "$ID" --network-alias pg \
  -e POSTGRES_PASSWORD=password --tmpfs /var/lib/postgresql/data postgres:14-alpine >/dev/null
docker run -d --name "$ID-redis" --network "$ID" --network-alias redis redis:8.10-alpine >/dev/null
for _ in $(seq 1 60); do
  docker exec "$ID-pg" pg_isready -U postgres -h 127.0.0.1 >/dev/null 2>&1 && break
  sleep 1
done
docker exec "$ID-pg" pg_isready -U postgres -h 127.0.0.1 >/dev/null

run() {
  local dir=$1 script=$2 redis=$3
  docker run --rm --network "$ID" --user "$(id -u):$(id -g)" \
    -e HOME=/tmp -e BUNDLE_PATH=/bundle -e RAILS_ENV=production -e RAILS_LOG_TO_STDOUT=1 \
    -e SECRET_KEY_BASE="$KEY" -e AWS_ACCESS_KEY_ID=probekey -e AWS_SECRET_ACCESS_KEY=probesecret \
    -e AWS_S3_REGION=eu-west-3 -e AWS_S3_BUCKET=probe -e HOST=https://localhost:3000 \
    -e DATABASE_URL=postgres://postgres:password@pg:5432/chaskiq_m12probe \
    -e REDIS_URL="$redis" -e DISABLE_DATABASE_ENVIRONMENT_CHECK=1 \
    -e DISABLE_AUTOLOAD_APPSTORE=true -e PROBE_RUBY="$script" \
    -v "$BUNDLE_DIR:/bundle" -v "$dir:/app" -v "$WORK/out:/out" -w /app "$IMG" \
    bash -c "${4:-bundle exec rails runner \"eval(ENV.fetch(%q(PROBE_RUBY)))\"}"
}
UP=redis://redis:6379/3
DOWN=redis://127.0.0.1:1/0

COMMON='
require "json"
T = Time.utc(2026, 11, 18, 10)
RAW = Redis.new(url: ENV.fetch("REDIS_URL"))
def snapshot
  RAW.keys("nf-production:*").sort.to_h { |k| [k, RAW.zrange(k, 0, -1, withscores: true)] }
end
def readings
  id = AppIdentity.new("m12app")
  { "range" => id.visits.get_range(T - 1.day, T + 2.days),
    "exact" => id.visits.get_exact(T + 1.day),
    "avg" => id.first_response_time.get_exact(T),
    "users" => id.new_users.get_range(T - 1.day, T + 1.day),
    "all" => id.visits.get_all,
    "twilio" => MessageApis::TwilioPhone::Store.get_values("m12conv/data"),
    "db0" => Redis.new(url: "redis://redis:6379/0").keys("*").sort }
end
'

WRITER="$COMMON"'
id = AppIdentity.new("m12app")
3.times { id.visits.incr(1, T) }
id.visits.incr(1, T + 1.day)
id.first_response_time.set(10, T)
id.first_response_time.set(20, T)
id.new_users.incr(2, T)
MessageApis::TwilioPhone::Store.set_data("m12conv", "agent", "42")
File.write("/out/base.json", JSON.dump("snap" => snapshot, "read" => readings))
puts "BASE WROTE #{snapshot.size} keys"
'

READER="$COMMON"'
base = JSON.parse(File.read("/out/base.json"))
before = JSON.parse(JSON.dump(snapshot))
fails = []
check = lambda do |name, ok, detail = nil|
  if ok then puts "ok #{name}" else fails << "#{name}: #{detail}" end
end
check.call("raw keys and members identical before the tree reads", before == base["snap"], before.keys.inspect)
check.call("keys keep the nf-production: prefix", before.keys.any? && before.keys.all? { |k| k.start_with?("nf-production:app_identity.m12app:") }, before.keys.inspect)
r = JSON.parse(JSON.dump(readings))
%w[range exact avg users twilio].each do |k|
  check.call("tree reads #{k} as BASE does", r[k] == base["read"][k] && !r[k].nil? && r[k] != {}, "tree=#{r[k].inspect} base=#{base["read"][k].inspect}")
end
check.call("get_all returns every data point", r["all"] == r["range"] && r["all"].size == 2, "all=#{r["all"].inspect} range=#{r["range"].inspect} base_all=#{base["read"]["all"].inspect}")
after = JSON.parse(JSON.dump(snapshot))
check.call("reading created or changed no key", after == before, (after.keys - before.keys).inspect)
require Rails.root.join("lib/rack/health_check").to_s
status, = Rack::HealthCheck.new.call({})
check.call("health check answers 200 with redis up", status == 200, status)
AppIdentity.new("m12app").visits.incr(1, T + 1.day)
check.call("BASE and tree data live in DB 3, DB 0 is empty", r["db0"] == [] && RAW.connection[:db] == 3 && RAW.exists?("/twilio_phone/m12conv/data"), r["db0"].inspect)
Kredis.namespace = "m12ns"
MessageApis::TwilioPhone::Store.set_data("m12ns-conv", "agent", "7")
Kredis.hash("/twilio_phone/m12ns-conv/data").update("extra" => "x")
got = MessageApis::TwilioPhone::Store.get_values("m12ns-conv/data")
check.call("Store.get_values honours Kredis.namespace", got == { "agent" => "7", "extra" => "x" } && RAW.hgetall("m12ns:/twilio_phone/m12ns-conv/data") == got, "got=#{got.inspect} raw=#{RAW.hgetall("m12ns:/twilio_phone/m12ns-conv/data").inspect}")
Kredis.namespace = nil
check.call("tree increments the existing series", AppIdentity.new("m12app").visits.get_exact(T + 1.day) == { (T + 1.day).beginning_of_day.to_i.to_s => "2" }, AppIdentity.new("m12app").visits.get_exact(T + 1.day).inspect)
fails.each { |f| puts "FAILED: #{f}" }
puts(fails.empty? ? "TREE READ OK" : "TREE READ FAILED")
'

DOWNCHECK='
require Rails.root.join("lib/rack/health_check").to_s
status, = Rack::HealthCheck.new.call({})
puts(status == 503 ? "ok health check answers 503 with redis down" : "FAILED: health check with redis down answered #{status}")
'

STAGING='
MessageApis::TwilioPhone::Store.set_data("m12stg", "agent", "9")
v = MessageApis::TwilioPhone::Store.get_values("m12stg/data")
raw = Redis.new(url: ENV.fetch("REDIS_URL")).hgetall("/twilio_phone/m12stg/data")
puts(v == { "agent" => "9" } && raw == v ? "ok staging Store writes and reads through Kredis" : "FAILED: staging Store #{v.inspect} raw #{raw.inspect}")
'

CYPRESS='
require "stringio"
err = StringIO.new
old = $stderr
$stderr = err
env = Rack::MockRequest.env_for("/__e2e__/command", method: "POST", "CONTENT_TYPE" => "application/json",
                                input: [{ name: "eval", options: "1 + 1" }].to_json)
status, = Rails.application.call(env)
$stderr = old
warn_lines = err.string.lines.grep(/deprecat/i)
puts(status == 201 && warn_lines.empty? ? "ok cypress /__e2e__/command answers 201 without deprecations" : "FAILED: cypress command #{status} #{warn_lines.inspect}")
'

BACK="$COMMON"'
v = AppIdentity.new("m12app").visits.get_exact(T + 1.day)
puts(v == { (T + 1.day).beginning_of_day.to_i.to_s => "2" } ? "ok BASE reads the value the tree wrote" : "FAILED: BASE reads #{v.inspect} after the tree wrote")
'

out=$(run "$WORK/base" "$WRITER" "$UP" 'bundle exec rails db:create db:schema:load >/dev/null && bundle exec rails runner "eval(ENV.fetch(%q(PROBE_RUBY)))"' 2>&1) \
  || { printf '%s\n' "$out" | tail -30; fail "BASE writer crashed"; }
printf '%s\n' "$out" | grep -q '^BASE WROTE [1-9]' || { printf '%s\n' "$out" | tail -30; fail "BASE wrote nothing"; }
echo "ok BASE wrote metrics and store data"

out=$(run "$WORK/tree" "$READER" "$UP" 2>&1) || { printf '%s\n' "$out" | tail -30; fail "tree reader crashed"; }
printf '%s\n' "$out" | grep -E '^(ok|FAILED:) '
printf '%s\n' "$out" | grep -q '^TREE READ OK$' || fail "tree does not read what BASE wrote"

out=$(run "$WORK/tree" "$DOWNCHECK" "$DOWN" 2>&1) || { printf '%s\n' "$out" | tail -30; fail "tree boot with redis down crashed"; }
printf '%s\n' "$out" | grep -E '^(ok|FAILED:) '
printf '%s\n' "$out" | grep -q '^ok health check answers 503' || fail "health check with redis down"

out=$(run "$WORK/tree" "$STAGING" "$UP" 'RAILS_ENV=staging bundle exec rails runner "eval(ENV.fetch(%q(PROBE_RUBY)))"' 2>&1) || { printf '%s\n' "$out" | tail -30; fail "staging Store run crashed"; }
printf '%s\n' "$out" | grep -E '^(ok|FAILED:) '
printf '%s\n' "$out" | grep -q '^ok staging Store' || fail "staging Store"

out=$(run "$WORK/tree" "$CYPRESS" "$UP" 'export RAILS_ENV=test DATABASE_URL=postgres://postgres:password@pg:5432/chaskiq_m12test && bundle exec rails db:create db:schema:load >/dev/null && bundle exec rails runner "eval(ENV.fetch(%q(PROBE_RUBY)))"' 2>&1) || { printf '%s\n' "$out" | tail -30; fail "cypress run crashed"; }
printf '%s\n' "$out" | grep -E '^(ok|FAILED:) '
printf '%s\n' "$out" | grep -q '^ok cypress' || fail "cypress command"

out=$(run "$WORK/base" "$BACK" "$UP" 2>&1) || { printf '%s\n' "$out" | tail -30; fail "BASE reader crashed"; }
printf '%s\n' "$out" | grep -E '^(ok|FAILED:) '
printf '%s\n' "$out" | grep -q '^ok BASE reads the value the tree wrote' || fail "BASE does not read what the tree wrote"
echo "M12 COMPAT PROBE PASS"
