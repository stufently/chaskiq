#!/usr/bin/env bash
# Probe for fork-updates-m1, package D: the two Docker image workflows use current
# action majors, $GITHUB_OUTPUT instead of set-output, and keep OUR image names/tags.
# Versions checked against GitHub releases on 2026-11-17: actions/checkout v7.0.1,
# docker/login-action v4.8.0, docker/metadata-action v6.2.0, docker/build-push-action v7.4.0.
set -u
H=.github/workflows/dockerimage.yml
G=.github/workflows/docker-image-ghcr.yml
fail=0
need() { grep -qE -- "$2" "$1" || { echo "FAIL: $1 lacks /$2/"; fail=1; }; }
deny() { if grep -qE -- "$2" "$1"; then echo "FAIL: $1 has /$2/"; fail=1; fi; }
for f in "$H" "$G"; do
  need "$f" 'uses: actions/checkout@v7([[:space:]]|$)'
  need "$f" 'uses: docker/login-action@v4([[:space:]]|$)'
  deny "$f" 'set-output'
  deny "$f" 'azure/docker-login'
  deny "$f" 'self-hosted'
  deny "$f" 'uses: [^@]+@(main|master)([[:space:]]|$)'
done
need "$G" 'uses: docker/metadata-action@v6([[:space:]]|$)'
need "$G" 'uses: docker/build-push-action@v7([[:space:]]|$)'
need "$G" 'IMAGE_NAME: \$\{\{ github\.repository \}\}'
need "$G" 'REGISTRY: ghcr\.io'
need "$G" 'type=ref,event=branch'
need "$G" 'type=ref,event=pr'
need "$G" '^[[:space:]]+type=sha[[:space:]]*$'
deny "$G" 'type=raw,value=latest'
deny "$G" 'type=sha,prefix='
need "$H" '>> "?\$GITHUB_OUTPUT"?'
need "$H" 'short_sha='
deny "$H" 'DOCKER_USERNAME \}\}/'
need "$H" 'docker push (\$GITHUB_REPOSITORY|\$\{\{ github\.repository \}\}):'
deny "$H" 'docker push "?\$IMAGE'
# checkout must precede the git rev-parse step in dockerimage.yml
co=$(grep -n 'actions/checkout@' "$H" | head -1 | cut -d: -f1)
rp=$(grep -n 'git rev-parse' "$H" | head -1 | cut -d: -f1)
if [ -z "$co" ] || [ -z "$rp" ] || [ "$co" -gt "$rp" ]; then echo "FAIL: $H must check out before git rev-parse"; fail=1; fi
[ "$fail" = 0 ] && echo "CI PROBE PASS"
exit "$fail"
