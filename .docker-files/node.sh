#!/usr/bin/env bash
set -euxo pipefail

install -d /etc/apt/keyrings

# NodeSource repository (the setup_N.x script is deprecated)
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
  | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" \
  > /etc/apt/sources.list.d/nodesource.list

# Debian trixie ships its own (newer-versioned) nodejs; without a pin apt
# would install that instead of NodeSource's NODE_MAJOR.
cat > /etc/apt/preferences.d/nodesource <<PREF
Package: nodejs
Pin: origin deb.nodesource.com
Pin-Priority: 1001
PREF

# Yarn repository
curl -fsSL https://dl.yarnpkg.com/debian/pubkey.gpg \
  | gpg --dearmor -o /etc/apt/keyrings/yarn.gpg
echo "deb [signed-by=/etc/apt/keyrings/yarn.gpg] https://dl.yarnpkg.com/debian/ stable main" \
  > /etc/apt/sources.list.d/yarn.list

# Install NodeJS, Yarn
apt-get update -qq && \
    DEBIAN_FRONTEND=noninteractive apt-get install -yq "nodejs=${NODE_MAJOR}.*" \
    "yarn=$YARN_VERSION-1"

# Fail the build if the wrong Node major got installed
node -v | grep -q "^v${NODE_MAJOR}\." || { echo "expected Node ${NODE_MAJOR}, got $(node -v)" >&2; exit 1; }
