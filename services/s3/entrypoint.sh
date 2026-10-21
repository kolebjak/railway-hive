#!/bin/sh
# Mount the volume at $S3_DATA_ROOT (default /srv). Buckets live in data/,
# the sidecar metadata outside it so it is not listed as a bucket.
set -eu

ROOT="${S3_DATA_ROOT:-/srv}"
mkdir -p "$ROOT/data/artifacts" "$ROOT/data/audit-logs" "$ROOT/metadata"

exec /usr/local/bin/versitygw \
  --port :9000 \
  --region us-east-1 \
  --health /minio/health/live \
  --disable-acl \
  posix --sidecar "$ROOT/metadata" "$ROOT/data"
