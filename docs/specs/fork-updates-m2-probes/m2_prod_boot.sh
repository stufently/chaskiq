#!/usr/bin/env bash
# Probe for fork-updates-m2: the production environment boots offline (eager_load, i.e.
# all app code incl. restored plugins) in both mail
# branches, and the SES branch registers a working ActionMailer delivery method that
# carries the configured credentials and region.
#   SMTP_DELIVERY_METHOD unset -> SES branch: delivery method ses or ses_v2, its settings hold
#     region from AWS_S3_REGION and the AWS_ACCESS_KEY_ID credentials, and a delivery through
#     the registered adapter with stubbed AWS responses succeeds;
#   SMTP_DELIVERY_METHOD=smtp  -> delivery method smtp.
# No network (--network none), dummy AWS credentials, no database needed for boot.
# development.rb is not booted here (i18n-js writes into the read-only tree); its SES branch
# is checked statically by m2_integrity_probe.py.
# Usage (from the repo root): bash docs/specs/fork-updates-m2-probes/m2_prod_boot.sh
set -euo pipefail
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
BUNDLE_DIR=${CHASKIQ_M1_BUNDLE:-$HOME/.cache/chaskiq-m1/bundle}
KEY=$(printf 'a%.0s' $(seq 64))
RUBY='require "./config/application"
Rails.application.initialize!
dm = ActionMailer::Base.delivery_method
out = "DM=#{dm} EL=#{Rails.application.config.eager_load}"
if %i[ses ses_v2].include?(dm)
  klass = ActionMailer::Base.delivery_methods.fetch(dm)
  settings = ActionMailer::Base.public_send("#{dm}_settings").to_h
  creds = settings[:credentials]
  key = creds.respond_to?(:access_key_id) ? creds.access_key_id : nil
  adapter = klass.new(settings.merge(stub_responses: true))
  adapter.deliver!(Mail.new(from: "probe@example.com", to: "to@example.com", subject: "s", body: "b"))
  out += " REGION=#{settings[:region]} KEY=#{key} DELIVERED=1"
end
puts out'
boot() {
  local env=$1; shift
  docker run --rm --network none --user "$(id -u):$(id -g)" \
    -e HOME=/tmp -e BUNDLE_PATH=/bundle -e RAILS_ENV="$env" -e RAILS_LOG_TO_STDOUT=1 \
    -e SECRET_KEY_BASE="$KEY" -e AWS_ACCESS_KEY_ID=probekey -e AWS_SECRET_ACCESS_KEY=probesecret \
    -e AWS_S3_REGION=eu-west-3 -e AWS_S3_BUCKET=probe -e HOST=http://localhost:3000 \
    -e DATABASE_URL=postgres://u:p@127.0.0.1:1/x -e REDIS_URL=redis://127.0.0.1:1/0 \
    -e DISABLE_AUTOLOAD_APPSTORE=true -e PROBE_RUBY="$RUBY" "$@" \
    -v "$BUNDLE_DIR:/bundle" -v "$ROOT:/app:ro" -w /app chaskiq-test:m1 \
    bash -c 'bundle exec ruby -e "$PROBE_RUBY"'
}
check() {
  local name=$1 want=$2 out=$3
  printf '%s\n' "$out" | grep -Eq "$want" || { printf '%s\n' "$out" | tail -20; echo "FAIL: $name"; exit 1; }
}
SES='^DM=(ses|ses_v2) EL=true REGION=eu-west-3 KEY=probekey DELIVERED=1$'
out=$(boot production 2>&1) || { printf '%s\n' "$out" | tail -20; echo "FAIL: production boot (SES branch) crashed"; exit 1; }
check "production SES branch" "$SES" "$out"
out=$(boot production -e SMTP_DELIVERY_METHOD=smtp 2>&1) || { printf '%s\n' "$out" | tail -20; echo "FAIL: production boot (SMTP branch) crashed"; exit 1; }
check "production SMTP branch" '^DM=smtp EL=true$' "$out"
echo "PROD BOOT PROBE PASS"
