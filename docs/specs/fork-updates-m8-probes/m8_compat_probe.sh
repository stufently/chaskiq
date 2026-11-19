#!/usr/bin/env bash
# Probe for fork-updates-m8 (config.load_defaults 7.0 -> 8.1): everything a live installation
# issued under the OLD defaults is still accepted by the NEW tree, and new tokens keep the
# shape the app code reads (symbol keys).
#
# 1. BASE = $(git merge-base HEAD @{u}) (override: M8_BASE) is exported with `git archive` and
#    must still say `config.load_defaults 7.0`; the current tracked tree must load 8.1.
# 2. One throwaway postgres + redis. BASE boots in production and issues: the encrypted session
#    cookie of a signed-in agent (Devise/Warden key), a signed cookie, the Devise remember cookie,
#    a messenger login token (CHASKIQ_VERIFIER, purpose :login), a plugin frame token
#    (CHASKIQ_FRAME_VERIFIER), an app message verifier token with purpose+expiry, an Active
#    Storage blob signed id, an Active Record signed id, a signed GlobalID, FileStore and
#    RedisCacheStore entries (string, hash with symbol keys, AR record) and a raw Rack::Attack
#    style counter.
# 3. The tree boots in production against the same DB/redis/secret and must accept every one of
#    them: the session cookie decodes and Warden's agent key resolves to the same agent, tokens
#    verify to equal payloads (symbol keys preserved), caches read back equal, the counter
#    continues (5 -> 6).
# 4. The tree issues a fresh messenger login token and plugin frame token and verifies them:
#    the payload must come back with SYMBOL keys (api_controller / connection.rb /
#    package_iframe_behavior read u[:email], data[:app_id]).
# Prints one "ok <name>" line per check and "M8 COMPAT PROBE PASS" at the end.
# Usage (from the repo root): bash docs/specs/fork-updates-m8-probes/m8_compat_probe.sh
set -euo pipefail
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
B=${M8_BASE:-$(git merge-base HEAD @{u})}
BUNDLE_DIR=${CHASKIQ_M6_BUNDLE:-$HOME/.cache/chaskiq-m6/bundle}
IMG=chaskiq-test:m1
KEY=$(printf 'b%.0s' $(seq 64))
ID="chqm8c-$(printf '%s' "$ROOT" | sha256sum | cut -c1-8)-$$"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/m8-compat.XXXXXX")
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
grep -Eq '^\s*config\.load_defaults 7\.0\s*$' "$WORK/base/config/application.rb" \
  || fail "BASE $B does not use config.load_defaults 7.0 (wrong merge-base?)"

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
  local dir=$1 script=$2
  docker run --rm --network "$ID" --user "$(id -u):$(id -g)" \
    -e HOME=/tmp -e BUNDLE_PATH=/bundle -e RAILS_ENV=production -e RAILS_LOG_TO_STDOUT=1 \
    -e SECRET_KEY_BASE="$KEY" -e AWS_ACCESS_KEY_ID=probekey -e AWS_SECRET_ACCESS_KEY=probesecret \
    -e AWS_S3_REGION=eu-west-3 -e AWS_S3_BUCKET=probe -e HOST=https://localhost:3000 \
    -e DATABASE_URL=postgres://postgres:password@pg:5432/chaskiq_m8probe \
    -e REDIS_URL=redis://redis:6379/0 -e DISABLE_DATABASE_ENVIRONMENT_CHECK=1 \
    -e DISABLE_AUTOLOAD_APPSTORE=true -e PROBE_RUBY="$script" \
    -v "$BUNDLE_DIR:/bundle" -v "$dir:/app" -v "$WORK/out:/out" -w /app "$IMG" \
    bash -c "$3"
}

WRITER='
require "json"
fs = ActiveSupport::Cache::FileStore.new("/out/cache")
rs = ActiveSupport::Cache::RedisCacheStore.new(url: ENV.fetch("REDIS_URL"))
agent = Agent.new(email: "m8probe@example.com", password: "M8-probe-password-123", name: "M8 Probe")
agent.save!(validate: false)
agent.remember_me!
env = Rails.application.env_config.merge("HTTP_HOST" => "localhost:3000", "HTTPS" => "on", "rack.url_scheme" => "https")
jar = ActionDispatch::Request.new(env).cookie_jar
session = { "session_id" => SecureRandom.hex(16), "warden.user.agent.key" => Agent.serialize_into_session(agent), "_csrf_token" => "m8" }
jar.encrypted["_chaskiq_session"] = { value: session }
jar.signed["m8_signed"] = { value: { "a" => 1 } }
jar.signed["remember_agent_token"] = { value: Agent.serialize_into_cookie(agent) }
blob = ActiveStorage::Blob.create!(key: "m8probe#{SecureRandom.hex(4)}", filename: "a.txt", byte_size: 1, checksum: "MQ==", content_type: "text/plain", service_name: ActiveStorage::Blob.service.name)
fs.write("m8:str", "v"); fs.write("m8:hash", { a: 1, "b" => [1, 2] }); fs.write("m8:rec", agent)
rs.write("m8:str", "v"); rs.write("m8:hash", { a: 1, "b" => [1, 2] }); rs.write("m8:rec", agent)
rs.increment("m8:ctr", 5, expires_in: 3600)
out = {
  "ld" => Rails.application.config.loaded_config_version.to_s,
  "agent_id" => agent.id, "blob_id" => blob.id,
  "cookies" => %w[_chaskiq_session m8_signed remember_agent_token].to_h { |k| [k, jar[k]] },
  "login" => CHASKIQ_VERIFIER.generate({ email: "visitor@example.com", type: "AppUser" }, purpose: :login),
  "frame" => CHASKIQ_FRAME_VERIFIER.generate({ app_id: "k1", package_id: 7 }),
  "mv" => Rails.application.message_verifier("m8probe").generate({ "x" => 1 }, purpose: :p, expires_in: 1.day),
  "blob_sid" => blob.signed_id,
  "agent_sid" => agent.signed_id(purpose: :m8probe),
  "sgid" => agent.to_sgid(for: "m8probe").to_s
}
File.write("/out/tokens.json", JSON.generate(out))
puts "BASE issued LD=#{out["ld"]}"
'

READER='
require "json"
t = JSON.parse(File.read("/out/tokens.json"))
$fails = []
def check(name)
  ok = begin
    yield
  rescue StandardError => e
    puts "  #{name}: #{e.class}: #{e.message.lines.first.to_s.strip}"
    false
  end
  if ok
    puts "ok #{name}"
  else
    $fails << name
  end
end
fails = $fails
ld = Rails.application.config.loaded_config_version.to_s
puts "TREE LD=#{ld}"
fails << "tree load_defaults is #{ld}, expected 8.1" unless ld == "8.1"
agent = Agent.find(t["agent_id"])
header = t["cookies"].map { |k, v| "#{k}=#{Rack::Utils.escape(v)}" }.join("; ")
env = Rails.application.env_config.merge("HTTP_HOST" => "localhost:3000", "HTTPS" => "on", "rack.url_scheme" => "https", "HTTP_COOKIE" => header)
jar = ActionDispatch::Request.new(env).cookie_jar
check("old session cookie keeps the agent signed in") do
  s = jar.encrypted["_chaskiq_session"]
  s.is_a?(Hash) && Agent.serialize_from_session(*s["warden.user.agent.key"]) == agent
end
check("old signed cookie") { jar.signed["m8_signed"] == { "a" => 1 } }
check("old remember cookie") { Agent.serialize_from_cookie(*jar.signed["remember_agent_token"]) == agent }
check("old messenger login token (symbol keys)") do
  CHASKIQ_VERIFIER.verify(t["login"], purpose: :login) == { email: "visitor@example.com", type: "AppUser" }
end
check("old plugin frame token (symbol keys)") { CHASKIQ_FRAME_VERIFIER.verify(t["frame"]) == { app_id: "k1", package_id: 7 } }
check("old app message verifier token") { Rails.application.message_verifier("m8probe").verify(t["mv"], purpose: :p) == { "x" => 1 } }
check("old Active Storage blob signed id") { ActiveStorage::Blob.find_signed!(t["blob_sid"]).id == t["blob_id"] }
check("old Active Record signed id") { Agent.find_signed!(t["agent_sid"], purpose: :m8probe) == agent }
check("old signed GlobalID") { GlobalID::Locator.locate_signed(t["sgid"], for: "m8probe") == agent }
fs = ActiveSupport::Cache::FileStore.new("/out/cache")
rs = ActiveSupport::Cache::RedisCacheStore.new(url: ENV.fetch("REDIS_URL"))
{ "FileStore" => fs, "RedisCacheStore" => rs }.each do |name, store|
  check("old #{name} entries read back") do
    store.read("m8:str") == "v" && store.read("m8:hash") == { a: 1, "b" => [1, 2] } && store.read("m8:rec")&.id == agent.id
  end
end
check("old counter continues") { rs.increment("m8:ctr", 1, expires_in: 3600) == 6 }
check("new messenger login token keeps symbol keys") do
  tok = CHASKIQ_VERIFIER.generate({ email: "new@example.com", type: "AppUser" }, purpose: :login)
  u = SessionFinder.get_by_cookie_session(tok)
  u.is_a?(Hash) && u[:email] == "new@example.com"
end
check("new plugin frame token keeps symbol keys") do
  CHASKIQ_FRAME_VERIFIER.verify(CHASKIQ_FRAME_VERIFIER.generate({ app_id: "k2", package_id: 8 }))[:app_id] == "k2"
end
if fails.empty?
  puts "M8 COMPAT PROBE PASS"
else
  puts "FAILED: #{fails.join("; ")}"
  exit 1
end
'

out=$(run "$WORK/base" "$WRITER" 'bundle exec rails db:create db:schema:load >/dev/null && bundle exec rails runner "eval(ENV.fetch(%q(PROBE_RUBY)))"' 2>&1) \
  || { printf '%s\n' "$out" | tail -25; fail "BASE could not issue artifacts"; }
printf '%s\n' "$out" | grep '^BASE issued' || { printf '%s\n' "$out" | tail -25; fail "BASE writer printed nothing"; }
out=$(run "$WORK/tree" "$READER" 'bundle exec rails runner "eval(ENV.fetch(%q(PROBE_RUBY)))"' 2>&1) && rc=0 || rc=$?
printf '%s\n' "$out" | grep -E '^(ok |TREE LD|  |FAILED|M8 COMPAT)' || printf '%s\n' "$out" | tail -25
[ "$rc" = 0 ] && printf '%s\n' "$out" | grep -q '^M8 COMPAT PROBE PASS$' || fail "tree rejected artifacts issued under the old defaults"
