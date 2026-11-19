#!/usr/bin/env bash
# Strict RuboCop on the milestone's Ruby files, same contract as CI / bin/ci-local:
# `bundle exec rubocop --force-exclusion` with the repo's .rubocop.yml + .rubocop_todo.yml,
# any offense fails. Files: every *.rb added or modified in BASE...HEAD, plus the m9 probe spec.
# Usage (clone root): bash docs/specs/fork-updates-m9-probes/m9_rubocop.sh <BASE_SHA>
# Needs: image chaskiq-test:m1, gems in $HOME/.cache/chaskiq-m6/bundle (CHASKIQ_BUNDLE overrides).
set -euo pipefail
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
B=${1:?usage: m9_rubocop.sh <BASE_SHA>}
BUNDLE_DIR=${CHASKIQ_BUNDLE:-$HOME/.cache/chaskiq-m6/bundle}
mapfile -t FILES < <(git diff --name-only --diff-filter=AM "$B" HEAD -- '*.rb')
FILES+=(docs/specs/fork-updates-m9-probes/m9_probe_spec.rb)
printf 'rubocop targets:\n'; printf '  %s\n' "${FILES[@]}"
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e BUNDLE_PATH=/bundle \
  -v "$BUNDLE_DIR:/bundle" -v "$ROOT:/app:ro" -w /app chaskiq-test:m1 \
  bash -c 'bundle exec rubocop --cache false --force-exclusion --format simple "$@"' _ "${FILES[@]}"
echo "M9 RUBOCOP PASS"
