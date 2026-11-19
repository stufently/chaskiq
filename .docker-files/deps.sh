#!/usr/bin/env bash
set -euxo pipefail

# Install Dependencies
apt-get update -qq \
  && DEBIAN_FRONTEND=noninteractive apt-get install -yq --no-install-recommends \
    build-essential \
    ca-certificates \
    gnupg \
    curl \
    less \
    git \
    imagemagick \
    libyaml-dev \
    pkg-config \
    zlib1g-dev
