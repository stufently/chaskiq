#!/usr/bin/env bash
set -euxo pipefail

install -d /etc/apt/keyrings

# NodeSource repository (the setup_N.x script is deprecated)
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
  | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" \
  > /etc/apt/sources.list.d/nodesource.list

# Yarn repository
curl -fsSL https://dl.yarnpkg.com/debian/pubkey.gpg \
  | gpg --dearmor -o /etc/apt/keyrings/yarn.gpg
echo "deb [signed-by=/etc/apt/keyrings/yarn.gpg] https://dl.yarnpkg.com/debian/ stable main" \
  > /etc/apt/sources.list.d/yarn.list

# Install NodeJS, Yarn
apt-get update -qq && \
    DEBIAN_FRONTEND=noninteractive apt-get install -yq nodejs \
    yarn=$YARN_VERSION-1
