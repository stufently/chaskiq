#!/usr/bin/env bash
# Live stand for fork-updates-m3 (production env, real postgres + redis, real puma).
#   1. frontend: yarn install --frozen-lockfile && yarn build (node:16 image);
#   2. assets:precompile (production, SKIP_JS_BUILD=1) into a fresh public/assets:
#      size <= MAX_MB, file count <= MAX_FILES, no node_modules package was copied (no
#      logical path ending in package.json), and the entry points the layouts use exist;
#   3. puma serves the home page (/); every /assets/*.css and *.js it references answers 200
#      with a css/javascript content type;
#   4. for each token path variant puma routes to doorkeeper (.xml, trailing slash, double
#      slash, .json/) and for a password grant in the query hidden behind a refresh_token
#      body: 20 posts pass, the 21st gets 429 (one client address per case via
#      X-Forwarded-For, see the spec on req.ip); the counters live in the redis from REDIS_URL.
# Measured on BASE 2835be9b (node_modules on the asset path): 848 MB, 78483 files.
# Same tree with node_modules off the asset path: 14 MB, 92 files.
# Usage (from the repo root): bash docs/specs/fork-updates-m3-probes/m3_stand_probe.sh
set -euo pipefail
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
MAX_MB=64
MAX_FILES=500
BUNDLE_DIR=${CHASKIQ_M1_BUNDLE:-$HOME/.cache/chaskiq-m1/bundle}
YARN_CACHE=${CHASKIQ_M1_YARN:-$HOME/.cache/chaskiq-m1/yarn}
KEY=$(printf 'a%.0s' $(seq 64))
ID="chqm3s-$(printf '%s' "$ROOT" | sha256sum | cut -c1-8)-$$"
cleanup() {
  docker rm -f "$ID-pg" "$ID-redis" >/dev/null 2>&1 || :
  docker network rm "$ID" >/dev/null 2>&1 || :
}
trap cleanup EXIT
fail() { echo "FAIL: $*"; exit 1; }

docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e YARN_CACHE_FOLDER=/ycache \
  -v "$YARN_CACHE:/ycache" -v "$ROOT:/app" -w /app node:16.20.2-bullseye-slim \
  sh -c "yarn install --frozen-lockfile --non-interactive --silent && yarn build" >/dev/null 2>&1 \
  || fail "frontend build"

ENVS=(-e HOME=/tmp -e BUNDLE_PATH=/bundle -e RAILS_ENV=production -e SECRET_KEY_BASE="$KEY"
  -e AWS_ACCESS_KEY_ID=probekey -e AWS_SECRET_ACCESS_KEY=probesecret -e AWS_S3_REGION=eu-west-3
  -e AWS_S3_BUCKET=probe -e HOST=http://localhost:3000 -e DISABLE_AUTOLOAD_APPSTORE=true
  -e SMTP_DELIVERY_METHOD=smtp -e RAILS_SERVE_STATIC_FILES=1 -e RAILS_LOG_TO_STDOUT=1
  -e DATABASE_URL=postgres://postgres:password@pg:5432/chaskiq_stand -e REDIS_URL=redis://redis:6379/5
  -e DISABLE_DATABASE_ENVIRONMENT_CHECK=1 -e SKIP_JS_BUILD=1)

mkdir -p tmp
rm -rf public/assets
docker run --rm --network none --user "$(id -u):$(id -g)" "${ENVS[@]}" \
  -v "$BUNDLE_DIR:/bundle" -v "$ROOT:/app" -w /app chaskiq-test:m1 \
  bundle exec rails assets:precompile >tmp/m3-precompile.log 2>&1 || { tail -20 tmp/m3-precompile.log; fail "assets:precompile"; }
mb=$(du -sm public/assets | cut -f1)
files=$(find public/assets -type f | wc -l)
echo "public/assets: ${mb} MB, ${files} files"
[ "$mb" -le "$MAX_MB" ] || fail "public/assets ${mb} MB > ${MAX_MB} MB"
[ "$files" -le "$MAX_FILES" ] || fail "public/assets ${files} files > ${MAX_FILES}"
manifest=public/assets/.manifest.json
test -s "$manifest" || fail "no propshaft manifest"
copied=$(jq -r 'keys[] | select(endswith("package.json"))' "$manifest" | head -5)
[ -z "$copied" ] || fail "node_modules packages copied into assets: $copied"
for logical in application.js application.css tailwind.css inter-font.css embed.js article.js logo.png favicon.png; do
  jq -e --arg k "$logical" 'has($k)' "$manifest" >/dev/null || fail "asset $logical missing from manifest"
done

docker network create "$ID" >/dev/null
docker run -d --name "$ID-pg" --network "$ID" --network-alias pg \
  -e POSTGRES_PASSWORD=password --tmpfs /var/lib/postgresql/data postgres:14-alpine >/dev/null
docker run -d --name "$ID-redis" --network "$ID" --network-alias redis redis:5-alpine >/dev/null
for _ in $(seq 1 60); do
  docker exec "$ID-pg" pg_isready -U postgres -h 127.0.0.1 >/dev/null 2>&1 && break
  sleep 1
done

STAND='set -euo pipefail
bundle exec rails db:create db:schema:load >/tmp/db.log 2>&1 || { tail -20 /tmp/db.log; echo "FAIL: db setup"; exit 1; }
bundle exec puma -b tcp://127.0.0.1:3000 -w 0 -t 1:2 -e production >/tmp/puma.log 2>&1 &
pid=$!
for _ in $(seq 1 90); do
  curl -fsS -o /dev/null http://localhost:3000/ 2>/dev/null && break
  kill -0 "$pid" 2>/dev/null || { tail -30 /tmp/puma.log; echo "FAIL: puma died"; exit 1; }
  sleep 1
done
code=$(curl -s -o /tmp/home.html -w "%{http_code}" http://localhost:3000/)
[ "$code" = 200 ] || { tail -30 /tmp/puma.log; echo "FAIL: home page $code"; exit 1; }
urls=$(grep -o -E "(href|src)=\"http://localhost:3000/assets/[^\"]+\.(css|js)\"" /tmp/home.html | sed -E "s/^(href|src)=\"//; s/\"$//" | sort -u)
[ -n "$urls" ] || { echo "FAIL: home page references no /assets css/js"; exit 1; }
for u in $urls; do
  out=$(curl -s -o /dev/null -w "%{http_code} %{content_type}" "$u")
  echo "asset $u -> $out"
  case "$u" in
    *.css) printf "%s\n" "$out" | grep -Eq "^200 text/css" || { echo "FAIL: $u"; exit 1; } ;;
    *.js) printf "%s\n" "$out" | grep -Eq "^200 (text|application)/javascript" || { echo "FAIL: $u"; exit 1; } ;;
  esac
done
hit() { curl -s --path-as-is -o /dev/null -w "%{http_code}" -X POST -H "X-Forwarded-For: $2" -d "$3" "http://localhost:3000$1"; }
n=0
for spec in "/oauth/token.xml|grant_type=password" "/oauth/token/|grant_type=password" "//oauth/token|grant_type=password" "/oauth/token.json/|grant_type=password" "/oauth/token?grant_type=password|grant_type=refresh_token&refresh_token=x"; do
  n=$((n + 1)); path=${spec%%|*}; body="${spec#*|}&email=stand@example.com&password=wrong"; ip="203.0.113.$n"
  for i in $(seq 1 20); do
    c=$(hit "$path" "$ip" "$body")
    [ "$c" != 429 ] && [ "$c" != 500 ] || { tail -30 /tmp/puma.log; echo "FAIL: request $i to $path got $c"; exit 1; }
  done
  c=$(hit "$path" "$ip" "$body")
  [ "$c" = 429 ] || { echo "FAIL: 21st password-grant request to $path got $c, want 429"; exit 1; }
  echo "throttled at 21: $path"
done
kill "$pid"
echo "STAND HTTP OK"'
docker run --rm --network "$ID" --user "$(id -u):$(id -g)" "${ENVS[@]}" -e STAND="$STAND" \
  -v "$BUNDLE_DIR:/bundle" -v "$ROOT:/app:ro" -v "$ROOT/public/assets:/app/public/assets:ro" -w /app \
  --tmpfs /app/tmp:uid="$(id -u)",gid="$(id -g)" --tmpfs /app/log:uid="$(id -u)",gid="$(id -g)" chaskiq-test:m1 \
  bash -c 'bash -c "$STAND"' || fail "stand"
keys=$(docker exec "$ID-redis" redis-cli -n 5 --scan --pattern '*logins/ip*')
[ -n "$keys" ] || fail "no Rack::Attack logins/ip counter in redis db 5"
echo "M3 STAND PROBE PASS"
