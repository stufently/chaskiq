#!/usr/bin/env bash
# Probe for fork-updates-m13 (rack 2.2 -> 3): the raw Rack pieces of the app follow the Rack 3
# spec and a real puma in production answers the same way on BASE (rack 2) and on the tree.
#
# 1. In-process, tree, test env: Rack::Lint wraps Middleware::MaintenanceMode and
#    Rack::HealthCheck (real redis) - no LintError (Rack 3 rejects upper-case header names).
# 2. BASE = $(git merge-base HEAD @{u}) (override: M13_BASE) via `git archive`; it must still be on
#    rack 2.2 and the tree on rack 3.2. Each tree boots puma (production, 1 worker thread pool)
#    against its own throwaway postgres + redis, seeds an agent and an OAuth application, and
#    answers this script (one line per request: "<name> <status> <detail>"):
#      health            GET  /health                               -> 200 + {"redis":{"connected":true}}
#      token_json        POST /oauth/token, JSON body, password grant -> 200 + access_token
#                        (Rack::Attack reads and rewinds the body first; the body must still reach
#                        doorkeeper)
#      token_form        POST /oauth/token, form body, password grant -> 200 + access_token
#      token_bad         POST /oauth/token, form body, wrong password -> 400 invalid_grant
#      sidekiq_noauth    GET  /sidekiq                               -> 401 + www-authenticate
#      sidekiq_auth      GET  /sidekiq/ with basic auth              -> 200 + "Sidekiq" in body
#      fwd_ip            Rack::Request#ip/#scheme in-process for REMOTE_ADDR 10.0.0.1 (trusted
#                        proxy), X-Forwarded-For 198.51.100.7, spoofed Forwarded for=1.2.3.4,
#                        X-Forwarded-Scheme https + X-Forwarded-Proto http -> "198.51.100.7 https"
#                        (rack 2 never reads Forwarded and prefers X-Forwarded-Scheme)
#      spoof_throttle    21 POST /oauth/token for an unknown e-mail through puma (a known one
#                        would get locked by Devise lockable), the same
#                        X-Forwarded-For and a different spoofed Forwarded: for=1.2.3.<n> each ->
#                        the 21st is 429 (Rack::Attack logins/ip keys on the X-Forwarded-For client)
#      devise_logout     an agent signed in by an encrypted session cookie + signed Devise remember
#                        cookie (both minted in-process with the app secret) calls
#                        DELETE /agents/sign_out (JSON) -> 200 {"a":"ok"}, and on the wire separate
#                        set-cookie lines for _chaskiq_session AND remember_agent_token (rack 3
#                        passes a cookie array, puma must split it). POST /agents/sign_in is not
#                        used: it answers 500 on BASE too (Agents::SessionsController#create calls
#                        Doorkeeper::AccessToken.find_or_create_for with positional arguments).
#      cable_good        AnyCable gRPC RPC server (`bundle exec anycable`, production) Connect with
#                        url /cable?token=<valid doorkeeper token> -> SUCCESS, identifiers name the agent
#      cable_bad         same with an unknown token -> the same status/identifiers on BASE and tree
# 3. The status+detail lines of BASE and tree must be identical and match the expectations above.
# Prints the lines, "ok lint ..." and "M13 HTTP PROBE PASS" at the end.
# Usage (from the repo root): bash docs/specs/fork-updates-m13-probes/m13_http_probe.sh
set -euo pipefail
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
B=${M13_BASE:-$(git merge-base HEAD @{u})}
BUNDLE_DIR=${CHASKIQ_M13_BUNDLE:-$HOME/.cache/chaskiq-m13/bundle}
IMG=${CHASKIQ_TEST_IMAGE:-chaskiq-test:m1}
KEY=$(printf 'd%.0s' $(seq 64))
ID="chqm13h-$(printf '%s' "$ROOT" | sha256sum | cut -c1-8)-$$"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/m13-http.XXXXXX")
cleanup() {
  for s in base tree; do docker rm -f "$ID-$s-pg" "$ID-$s-redis" >/dev/null 2>&1 || :; done
  docker network rm "$ID" >/dev/null 2>&1 || :
  rm -rf -- "$WORK"
}
trap cleanup EXIT
fail() { echo "FAIL: $*"; exit 1; }

mkdir -p "$WORK/base" "$WORK/tree"
git archive "$B" | tar -xf - -C "$WORK/base"
git ls-files -z | tar --null -T - -cf - | tar -xf - -C "$WORK/tree"
grep -Eq '^    rack \(2\.2\.' "$WORK/base/Gemfile.lock" || fail "BASE $B is not on rack 2.2 (wrong merge-base?)"
grep -Eq '^    rack \(3\.2\.' "$WORK/tree/Gemfile.lock" || fail "tree Gemfile.lock is not on rack 3.2"
docker network create "$ID" >/dev/null

LINT='
require "rack/lint"
require "rack/mock_request"
require Rails.root.join("config/middleware/maintenance_mode").to_s
require Rails.root.join("lib/rack/health_check").to_s
{ "maintenance" => Middleware::MaintenanceMode.new(nil), "health" => Rack::HealthCheck.new }.each do |name, app|
  status, headers, body = Rack::Lint.new(app).call(Rack::MockRequest.env_for("/"))
  body.each { |_| nil }
  body.close if body.respond_to?(:close)
  bad = headers.keys.grep(/[A-Z]/)
  raise "upper-case header names #{bad}" if bad.any?
  puts "ok lint #{name}: #{status} #{headers.keys.sort.join(",")}"
rescue StandardError => e
  puts "FAILED: lint #{name}: #{e.class}: #{e.message}"
end
'

STAND='set -euo pipefail
bundle exec rails db:create db:schema:load >/tmp/db.log 2>&1 || { tail -20 /tmp/db.log; echo "FAIL: db setup"; exit 1; }
bundle exec rails runner "
a = Agent.new(email: %q(m13@example.com), password: %q(M13-probe-password-1), name: %q(M13))
a.save!(validate: false)
oa = Doorkeeper::Application.create!(name: %q(m13), uid: %q(m13uid), secret: %q(m13secret), redirect_uri: %q(urn:ietf:wg:oauth:2.0:oob), scopes: %q(read), confidential: false)
Doorkeeper::AccessToken.create!(application: oa, resource_owner_id: a.id, scopes: %q(read), expires_in: 3600).update_column(:token, %q(m13cabletoken))
a.remember_me!
jar = ActionDispatch::Request.new(Rails.application.env_config.merge(%q(HTTP_HOST) => %q(localhost:3000))).cookie_jar
jar.encrypted[%q(_chaskiq_session)] = { value: { %q(session_id) => SecureRandom.hex(16), %q(warden.user.agent.key) => Agent.serialize_into_session(a) } }
jar.signed[%q(remember_agent_token)] = { value: Agent.serialize_into_cookie(a) }
File.write(%q(/tmp/cookies), %w[_chaskiq_session remember_agent_token].map { |k| %Q(#{k}=#{Rack::Utils.escape(jar[k])}) }.join(%q(; )))
env = Rack::MockRequest.env_for(%q(/), %q(REMOTE_ADDR) => %q(10.0.0.1), %q(HTTP_X_FORWARDED_FOR) => %q(198.51.100.7),
  %q(HTTP_FORWARDED) => %q(for=1.2.3.4;proto=http), %q(HTTP_X_FORWARDED_SCHEME) => %q(https), %q(HTTP_X_FORWARDED_PROTO) => %q(http))
r = Rack::Request.new(env)
File.write(%q(/tmp/fwd), %Q(fwd_ip 200 #{r.ip} #{r.scheme}))
" >/tmp/seed.log 2>&1 || { tail -20 /tmp/seed.log; echo "FAIL: seed"; exit 1; }
cat /tmp/fwd; echo
ANYCABLE_RPC_HOST=127.0.0.1:50051 ANYCABLE_BROADCAST_ADAPTER=redis bundle exec anycable >/tmp/anycable.log 2>&1 &
apid=$!
bundle exec puma -b tcp://127.0.0.1:3000 -w 0 -t 1:2 -e production >/tmp/puma.log 2>&1 &
pid=$!
for _ in $(seq 1 90); do
  curl -s -o /dev/null http://localhost:3000/health 2>/dev/null && break
  kill -0 "$pid" 2>/dev/null || { tail -30 /tmp/puma.log; echo "FAIL: puma died"; exit 1; }
  sleep 1
done
U=http://localhost:3000
req() { curl -s -o /tmp/body -D /tmp/head -w "%{http_code}" "$@"; }
c=$(req "$U/health"); echo "health $c $(tr -d "\n" < /tmp/body)"
c=$(req -X POST -H "Content-Type: application/json" -H "X-Forwarded-For: 203.0.113.1" \
  -d "{\"grant_type\":\"password\",\"email\":\"m13@example.com\",\"password\":\"M13-probe-password-1\",\"client_id\":\"m13uid\",\"client_secret\":\"m13secret\"}" "$U/oauth/token")
echo "token_json $c $(grep -o "\"access_token\"" /tmp/body | head -1)"
c=$(req -X POST -H "X-Forwarded-For: 203.0.113.2" \
  -d "grant_type=password&email=m13@example.com&password=M13-probe-password-1&client_id=m13uid&client_secret=m13secret" "$U/oauth/token")
echo "token_form $c $(grep -o "\"access_token\"" /tmp/body | head -1)"
c=$(req -X POST -H "X-Forwarded-For: 203.0.113.3" \
  -d "grant_type=password&email=m13@example.com&password=wrong&client_id=m13uid&client_secret=m13secret" "$U/oauth/token")
echo "token_bad $c $(grep -o "invalid_grant" /tmp/body | head -1)"
c=$(req "$U/sidekiq"); echo "sidekiq_noauth $c $(grep -ic "^www-authenticate:" /tmp/head)"
c=$(req -L -u "admin@example.com:m13-admin" "$U/sidekiq/"); echo "sidekiq_auth $c $(grep -c "Sidekiq" /tmp/body | sed "s/^[1-9][0-9]*$/has-sidekiq/")"
for n in $(seq 1 21); do
  c=$(req -X POST -H "X-Forwarded-For: 198.51.100.7" -H "Forwarded: for=1.2.3.$n" \
    -d "grant_type=password&email=nobody-m13@example.com&password=wrong&client_id=m13uid&client_secret=m13secret" "$U/oauth/token")
done
echo "spoof_throttle $c"
c=$(req -X DELETE -H "Accept: application/json" -H "Cookie: $(cat /tmp/cookies)" "$U/agents/sign_out")
echo "devise_logout $c $(grep -o "\"a\":\"ok\"" /tmp/body | head -1) set-cookie=$(grep -ic "^set-cookie:" /tmp/head) session=$(grep -ic "^set-cookie: _chaskiq_session=" /tmp/head) remember=$(grep -ic "^set-cookie: remember_agent_token=" /tmp/head)"
for _ in $(seq 1 60); do
  grep -q "RPC server is listening\|Serving RPC" /tmp/anycable.log 2>/dev/null && break
  kill -0 "$apid" 2>/dev/null || break
  sleep 1
done
bundle exec ruby -e "
require %q(json)
require %q(anycable)
require %q(anycable/grpc)
require %q(anycable/grpc/rpc_services_pb)
stub = AnyCable::GRPC::Stub.new(%q(127.0.0.1:50051), :this_channel_is_insecure, timeout: 20)
{ %q(cable_good) => %q(m13cabletoken), %q(cable_bad) => %q(nope) }.each do |name, token|
  env = AnyCable::Env.new(url: %Q(http://localhost:3000/cable?token=#{token}), headers: { %q(origin) => %q(http://localhost:3000) })
  res = stub.connect(AnyCable::ConnectionRequest.new(env: env), metadata: { %q(protov) => %q(v1) })
  ids = res.identifiers.to_s.empty? ? {} : JSON.parse(res.identifiers)
  agent = ids.values.any? { |v| v.to_s.include?(%q(Agent)) || v.to_s.tr(%q(-_), %q(+/)).unpack1(%q(m)).include?(%q(/Agent/)) }
  puts %Q(#{name} #{res.status} agent=#{agent ? %q(yes) : %q(no)})
rescue StandardError => e
  puts %Q(#{name} ERROR #{e.class})
end
" 2>/tmp/cable.err || { tail -5 /tmp/cable.err; tail -20 /tmp/anycable.log; }
kill "$apid" 2>/dev/null || :
kill "$pid"
echo "STAND DONE"'

run_stand() {
  local side=$1 dir=$2
  docker run -d --name "$ID-$side-pg" --network "$ID" --network-alias "$side-pg" \
    -e POSTGRES_PASSWORD=password --tmpfs /var/lib/postgresql/data postgres:14-alpine >/dev/null
  docker run -d --name "$ID-$side-redis" --network "$ID" --network-alias "$side-redis" redis:8.10-alpine >/dev/null
  for _ in $(seq 1 60); do
    docker exec "$ID-$side-pg" pg_isready -U postgres -h 127.0.0.1 >/dev/null 2>&1 && break
    sleep 1
  done
  docker run --rm --network "$ID" --user "$(id -u):$(id -g)" \
    -e HOME=/tmp -e BUNDLE_PATH=/bundle -e RAILS_ENV=production -e SECRET_KEY_BASE="$KEY" \
    -e AWS_ACCESS_KEY_ID=probekey -e AWS_SECRET_ACCESS_KEY=probesecret -e AWS_S3_REGION=eu-west-3 \
    -e AWS_S3_BUCKET=probe -e HOST=http://localhost:3000 -e DISABLE_AUTOLOAD_APPSTORE=true \
    -e RAILS_LOG_TO_STDOUT=1 -e DISABLE_DATABASE_ENVIRONMENT_CHECK=1 \
    -e ADMIN_EMAIL=admin@example.com -e ADMIN_PASSWORD=m13-admin \
    -e DATABASE_URL="postgres://postgres:password@$side-pg:5432/chaskiq_m13" \
    -e REDIS_URL="redis://$side-redis:6379/0" -e STAND="$STAND" \
    -v "$BUNDLE_DIR:/bundle" -v "$dir:/app" -w /app \
    --tmpfs /app/tmp:uid="$(id -u)",gid="$(id -g)" --tmpfs /app/log:uid="$(id -u)",gid="$(id -g)" "$IMG" \
    bash -c 'bundle install --quiet && bash -c "$STAND"'
}

# 1. lint, tree, test env
lint_out=$(docker run --rm --network "$ID" --user "$(id -u):$(id -g)" \
  -e HOME=/tmp -e BUNDLE_PATH=/bundle -e RAILS_ENV=test -e PROBE_RUBY="$LINT" \
  -e DATABASE_URL=postgres://u:p@127.0.0.1:1/x -e REDIS_URL=redis://127.0.0.1:1/0 \
  -v "$BUNDLE_DIR:/bundle" -v "$WORK/tree:/app" -w /app "$IMG" \
  bash -c 'bundle install --quiet && bundle exec rails runner "eval(ENV.fetch(%q(PROBE_RUBY)))"' 2>&1) \
  || { printf '%s\n' "$lint_out" | tail -20; fail "lint run crashed"; }
printf '%s\n' "$lint_out" | grep -E '^(ok|FAILED:) lint'
[ "$(printf '%s\n' "$lint_out" | grep -c '^ok lint')" = 2 ] || fail "Rack::Lint rejects app middleware on rack 3"

# 2. stands
base_out=$(run_stand base "$WORK/base" 2>&1) || { printf '%s\n' "$base_out" | tail -30; fail "BASE stand"; }
tree_out=$(run_stand tree "$WORK/tree" 2>&1) || { printf '%s\n' "$tree_out" | tail -30; fail "tree stand"; }
pick() { printf '%s\n' "$1" | grep -E '^(health|token_json|token_form|token_bad|sidekiq_noauth|sidekiq_auth|fwd_ip|spoof_throttle|devise_logout|cable_good|cable_bad) '; }
b=$(pick "$base_out"); t=$(pick "$tree_out")
printf 'BASE:\n%s\nTREE:\n%s\n' "$b" "$t"
want='health 200 {"redis":{"connected":true}}
token_json 200 "access_token"
token_form 200 "access_token"
token_bad 400 invalid_grant
sidekiq_noauth 401 1
sidekiq_auth 200 has-sidekiq'
want_tail='fwd_ip 200 198.51.100.7 https
spoof_throttle 429
devise_logout 200 "a":"ok" set-cookie=2 session=1 remember=1
cable_good SUCCESS agent=yes'
got_want=$(printf '%s\n' "$b" | grep -Ev '^(fwd_ip|spoof_throttle|devise_logout|cable_good|cable_bad) ')
got_tail=$(printf '%s\n' "$b" | grep -E '^(fwd_ip|spoof_throttle|devise_logout|cable_good) ')
[ "$got_want" = "$want" ] || fail "BASE (rack 2) does not answer as expected - probe or environment defect"
[ "$got_tail" = "$want_tail" ] || fail "BASE (rack 2) forwarded/login/cable lines differ from the expectation - probe or environment defect"
printf '%s\n' "$b" | grep -q '^cable_bad ' || fail "BASE gave no cable_bad line"
[ "$t" = "$b" ] || fail "tree (rack 3) answers differently from BASE (rack 2)"
echo "M13 HTTP PROBE PASS"
