#!/bin/sh
# Regenerate requirements.lock from upstream's requirements.txt at the commit
# pinned in the Dockerfile. Review the diff before committing.
set -eu
cd "$(dirname "$0")/.."

commit=$(sed -n 's/^ARG UPSTREAM_COMMIT=//p' Dockerfile)
[ -n "$commit" ] || { echo "UPSTREAM_COMMIT not found in Dockerfile" >&2; exit 1; }

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
curl -fsSL "https://raw.githubusercontent.com/dgtlmoon/changedetection.io/$commit/requirements.txt" -o "$tmp"

uv pip compile --quiet \
  --generate-hashes \
  --python-version 3.11 \
  --python-platform x86_64-manylinux_2_36 \
  --only-binary :all: \
  --no-binary feedgen \
  --no-header \
  --no-annotate \
  "$tmp" -o requirements.lock

echo "Locked $(grep -c '^[A-Za-z0-9_.-]*==' requirements.lock) packages for upstream $commit"
