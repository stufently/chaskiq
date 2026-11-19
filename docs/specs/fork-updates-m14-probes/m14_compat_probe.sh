#!/usr/bin/env bash
# Probe for fork-updates-m14 (Ruby 3.3 -> 4.0), both directions: everything a live installation
# running on Ruby 3.3 issued (Marshal/JSON payloads, cookies, caches) is accepted by the tree on
# Ruby 4.0, AND everything the tree on Ruby 4.0 issued is accepted by BASE on Ruby 3.3 (rollback,
# staged rollout with mixed Ruby versions on one DB/redis/secret).
# Same checks as docs/specs/fork-updates-m8-probes/m8_compat_probe.sh, but BASE and tree run on
# different Ruby builds:
# 1. BASE = $(git merge-base HEAD @{u}) (override: M14_BASE) via `git archive`; its Gemfile must pin
#    ruby 3.3.x and the tree ruby 4.0.x.
# 2. One throwaway postgres + redis. BASE boots in production on chaskiq-test:m1-ruby3314 with the
#    gems of $HOME/.cache/chaskiq-m13/bundle and issues: the encrypted session cookie of a
#    signed-in agent, a signed cookie, the Devise remember cookie, a messenger login token
#    (CHASKIQ_VERIFIER, Marshal), a plugin frame token (CHASKIQ_FRAME_VERIFIER), an app message
#    verifier token with purpose+expiry, an Active Storage blob signed id, an Active Record signed
#    id, a signed GlobalID, FileStore and RedisCacheStore entries (string, hash with symbol keys,
#    AR record - Marshal across Ruby versions) and a raw Rack::Attack style counter.
# 3. The tree boots in production on chaskiq-test:m1 (Ruby 4.0) with $HOME/.cache/chaskiq-m14/bundle
#    against the same DB/redis/secret and must accept every one of them; fresh tokens keep symbol
#    keys.
# 4. Back: the tree on Ruby 4.0 issues the same set (own agent, own cache keys and dir), BASE on
#    Ruby 3.3 must accept every one of them.
# Prints one "ok <name>" line per check and "M14 COMPAT PROBE PASS" at the end.
# Usage (from the repo root): bash docs/specs/fork-updates-m14-probes/m14_compat_probe.sh
set -euo pipefail
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
B=${M14_BASE:-$(git merge-base HEAD @{u})}
BASE_BUNDLE=${CHASKIQ_M13_BUNDLE:-$HOME/.cache/chaskiq-m13/bundle}
BASE_IMG=${CHASKIQ_BASE_IMAGE:-chaskiq-test:m1-ruby3314}
TREE_BUNDLE=${CHASKIQ_M14_BUNDLE:-$HOME/.cache/chaskiq-m14/bundle}
TREE_IMG=${CHASKIQ_TEST_IMAGE:-chaskiq-test:m1}
KEY=$(printf 'b%.0s' $(seq 64))
ID="chqm14c-$(printf '%s' "$ROOT" | sha256sum | cut -c1-8)-$$"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/m14-compat.XXXXXX")
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
grep -Eq '^ruby "3\.3\.' "$WORK/base/Gemfile" || fail "BASE $B does not pin ruby 3.3 (wrong merge-base?)"
grep -Eq '^ruby "4\.0\.' "$WORK/tree/Gemfile" || fail "tree Gemfile does not pin ruby 4.0"

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
  local dir=$1 script=$2 img bundle
  if [ "$dir" = "$WORK/base" ]; then img=$BASE_IMG bundle=$BASE_BUNDLE; else img=$TREE_IMG bundle=$TREE_BUNDLE; fi
  docker run --rm --network "$ID" --user "$(id -u):$(id -g)" \
    -e HOME=/tmp -e BUNDLE_PATH=/bundle -e RAILS_ENV=production -e RAILS_LOG_TO_STDOUT=1 \
    -e SECRET_KEY_BASE="$KEY" -e AWS_ACCESS_KEY_ID=probekey -e AWS_SECRET_ACCESS_KEY=probesecret \
    -e AWS_S3_REGION=eu-west-3 -e AWS_S3_BUCKET=probe -e HOST=https://localhost:3000 \
    -e DATABASE_URL=postgres://postgres:password@pg:5432/chaskiq_m14probe \
    -e REDIS_URL=redis://redis:6379/0 -e DISABLE_DATABASE_ENVIRONMENT_CHECK=1 \
    -e DISABLE_AUTOLOAD_APPSTORE=true -e PROBE_RUBY="$script" -e P="$4" -e SIDE="$5" -e EXPECT_RUBY="$6" \
    -v "$bundle:/bundle" -v "$dir:/app" -v "$WORK/out:/out" -w /app "$img" \
    bash -c "$3"
}

WRITER='
require "json"
P = ENV.fetch("P")
FileUtils.mkdir_p("/out/#{P}")
fs = ActiveSupport::Cache::FileStore.new("/out/#{P}/cache")
rs = ActiveSupport::Cache::RedisCacheStore.new(url: ENV.fetch("REDIS_URL"))
agent = Agent.new(email: "m14#{P}@example.com", password: "M8-probe-password-123", name: "M8 Probe")
agent.save!(validate: false)
agent.remember_me!
env = Rails.application.env_config.merge("HTTP_HOST" => "localhost:3000", "HTTPS" => "on", "rack.url_scheme" => "https")
jar = ActionDispatch::Request.new(env).cookie_jar
session = { "session_id" => SecureRandom.hex(16), "warden.user.agent.key" => Agent.serialize_into_session(agent), "_csrf_token" => "m8" }
jar.encrypted["_chaskiq_session"] = { value: session }
jar.signed["m8_signed"] = { value: { "a" => 1 } }
jar.signed["remember_agent_token"] = { value: Agent.serialize_into_cookie(agent) }
blob = ActiveStorage::Blob.create!(key: "m14#{P}#{SecureRandom.hex(4)}", filename: "a.txt", byte_size: 1, checksum: "MQ==", content_type: "text/plain", service_name: ActiveStorage::Blob.service.name)
fs.write("#{P}:str", "v"); fs.write("#{P}:hash", { a: 1, "b" => [1, 2] }); fs.write("#{P}:rec", agent)
rs.write("#{P}:str", "v"); rs.write("#{P}:hash", { a: 1, "b" => [1, 2] }); rs.write("#{P}:rec", agent)
rs.increment("#{P}:ctr", 5, expires_in: 3600)
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
File.write("/out/#{P}/tokens.json", JSON.generate(out))
puts "#{ENV.fetch("SIDE")} issued LD=#{out["ld"]} RUBY=#{RUBY_VERSION}"
'

READER='
require "json"
P = ENV.fetch("P")
t = JSON.parse(File.read("/out/#{P}/tokens.json"))
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
side = ENV.fetch("SIDE")
puts "#{side} LD=#{ld}"
fails << "#{side} load_defaults is #{ld}, expected 8.1" unless ld == "8.1"
puts "#{side} RUBY=#{RUBY_VERSION}"
fails << "#{side} runs Ruby #{RUBY_VERSION}, expected #{ENV.fetch("EXPECT_RUBY")}.x" unless RUBY_VERSION.start_with?("#{ENV.fetch("EXPECT_RUBY")}.")
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
fs = ActiveSupport::Cache::FileStore.new("/out/#{P}/cache")
rs = ActiveSupport::Cache::RedisCacheStore.new(url: ENV.fetch("REDIS_URL"))
{ "FileStore" => fs, "RedisCacheStore" => rs }.each do |name, store|
  check("old #{name} entries read back") do
    store.read("#{P}:str") == "v" && store.read("#{P}:hash") == { a: 1, "b" => [1, 2] } && store.read("#{P}:rec")&.id == agent.id
  end
end
check("old counter continues") { rs.increment("#{P}:ctr", 1, expires_in: 3600) == 6 }
check("new messenger login token keeps symbol keys") do
  tok = CHASKIQ_VERIFIER.generate({ email: "new@example.com", type: "AppUser" }, purpose: :login)
  u = SessionFinder.get_by_cookie_session(tok)
  u.is_a?(Hash) && u[:email] == "new@example.com"
end
check("new plugin frame token keeps symbol keys") do
  CHASKIQ_FRAME_VERIFIER.verify(CHASKIQ_FRAME_VERIFIER.generate({ app_id: "k2", package_id: 8 }))[:app_id] == "k2"
end
if fails.empty?
  puts "#{side} ACCEPTED ALL"
else
  puts "FAILED: #{fails.join("; ")}"
  exit 1
end
'

R='bundle exec rails runner "eval(ENV.fetch(%q(PROBE_RUBY)))"'
# forward: BASE (3.3) issues, tree (4.0) accepts
out=$(run "$WORK/base" "$WRITER" "bundle exec rails db:create db:schema:load >/dev/null && $R" a BASE 3.3 2>&1) \
  || { printf '%s\n' "$out" | tail -25; fail "BASE could not issue artifacts"; }
printf '%s\n' "$out" | grep '^BASE issued' || { printf '%s\n' "$out" | tail -25; fail "BASE writer printed nothing"; }
out=$(run "$WORK/tree" "$READER" "$R" a TREE 4.0 2>&1) && rc=0 || rc=$?
printf '%s\n' "$out" | grep -E '^(ok |TREE LD|TREE RUBY|  |FAILED|TREE ACCEPTED)' | sed 's/^ok /ok forward: /' || printf '%s\n' "$out" | tail -25
[ "$rc" = 0 ] && printf '%s\n' "$out" | grep -q '^TREE ACCEPTED ALL$' || fail "tree on Ruby 4.0 rejected artifacts issued on Ruby 3.3"
# back: tree (4.0) issues, BASE (3.3) accepts - rollback and mixed rollout
out=$(run "$WORK/tree" "$WRITER" "$R" b TREE 4.0 2>&1) \
  || { printf '%s\n' "$out" | tail -25; fail "tree could not issue artifacts"; }
printf '%s\n' "$out" | grep '^TREE issued' || { printf '%s\n' "$out" | tail -25; fail "tree writer printed nothing"; }
out=$(run "$WORK/base" "$READER" "$R" b BASE 3.3 2>&1) && rc=0 || rc=$?
printf '%s\n' "$out" | grep -E '^(ok |BASE LD|BASE RUBY|  |FAILED|BASE ACCEPTED)' | sed 's/^ok /ok back: /' || printf '%s\n' "$out" | tail -25
[ "$rc" = 0 ] && printf '%s\n' "$out" | grep -q '^BASE ACCEPTED ALL$' || fail "BASE on Ruby 3.3 rejected artifacts issued on Ruby 4.0 (no rollback)"
echo "M14 COMPAT PROBE PASS"
