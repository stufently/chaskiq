#!/usr/bin/env bash
set -euxo pipefail

# Set PG_MAJOR if not set, default to 14
PG_MAJOR=${PG_MAJOR:-14}
CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")

# PGDG repository for the base image's Debian release (apt-key is gone in trixie)
install -d /etc/apt/keyrings
curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
  | gpg --dearmor -o /etc/apt/keyrings/pgdg.gpg
echo "deb [signed-by=/etc/apt/keyrings/pgdg.gpg] http://apt.postgresql.org/pub/repos/apt ${CODENAME}-pgdg main" \
  > /etc/apt/sources.list.d/pgdg.list

# Update the package list and install dependencies
apt-get update -qq && \
  DEBIAN_FRONTEND=noninteractive apt-get install -yq --no-install-recommends \
  libpq5 \
  libpq-dev \
  postgresql-client-${PG_MAJOR}
