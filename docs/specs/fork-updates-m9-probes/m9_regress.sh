#!/usr/bin/env bash
# Regression set for fork-updates-m9 (main after m8: Rails 8.1.4.1, load_defaults 8.1, Ruby 3.3.14).
# Usage (clone root): bash docs/specs/fork-updates-m9-probes/m9_regress.sh <BASE_SHA>
# Gems from $HOME/.cache/chaskiq-m6/bundle (CHASKIQ_BUNDLE overrides). Runs: the m8 boot probe
# (4 environments, load_defaults 8.1, no deprecations); runtime probes m1, m2, Rack::Attack m3,
# blocks m4, attachments m5, attachments/SafeDownload m7; boot probes m2, m3, m4; redis from
# compose; puma and config m1; tree and supply-chain probe over BASE...HEAD.
set -euo pipefail
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
B=${1:?usage: m9_regress.sh <BASE_SHA>}
G=docs/specs/fork-updates-m9-probes/rspec_gate_m9.sh
export CHASKIQ_M1_BUNDLE=${CHASKIQ_BUNDLE:-$HOME/.cache/chaskiq-m6/bundle}
export CHASKIQ_BUNDLE=$CHASKIQ_M1_BUNDLE CHASKIQ_M6_BUNDLE=$CHASKIQ_M1_BUNDLE
bash docs/specs/fork-updates-m8-probes/m8_boot_probe.sh
for s in m1-probes/m1_runtime_probe_spec.rb m2-probes/m2_runtime_probe_spec.rb \
         m3-probes/m3_attack_probe_spec.rb m4-probes/m4_blocks_probe_spec.rb \
         m5-probes/m5_media_probe_spec.rb m7-probes/m7_probe_spec.rb; do
  bash "$G" --only "docs/specs/fork-updates-$s"
done
bash docs/specs/fork-updates-m2-probes/m2_prod_boot.sh
bash docs/specs/fork-updates-m3-probes/m3_boot_probe.sh
bash docs/specs/fork-updates-m4-probes/m4_boot_probe.sh
bash docs/specs/fork-updates-m4-probes/m4_compose_probe.sh
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e BUNDLE_PATH=/bundle \
  -v "$CHASKIQ_M1_BUNDLE:/bundle" -v "$PWD:/app:ro" -w /app chaskiq-test:m1 \
  bash -c "bundle exec ruby docs/specs/fork-updates-m1-probes/m1_puma_probe.rb && ruby docs/specs/fork-updates-m1-probes/m1_config_probe.rb"
python3 -I docs/specs/fork-updates-m5-probes/m5_tree_probe.py "$B"
echo "M9 REGRESSION PASS"
