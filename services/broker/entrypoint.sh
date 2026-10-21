#!/usr/bin/env bash
# Single-node Redpanda. Listens on [::] (Railway's private network is IPv6) and
# advertises its private domain so clients resolve it. Upstream's compose command
# references a `redpanda-1` seed that does not exist; dev-container mode replaces it.
set -euo pipefail

DATA_DIR=/var/lib/redpanda/data
# Railway sets RAILWAY_PRIVATE_DOMAIN; compose relies on `hostname: broker`.
ADVERTISE_HOST="${BROKER_ADVERTISE_HOST:-${RAILWAY_PRIVATE_DOMAIN:-$(hostname)}}"
MEMORY="${REDPANDA_MEMORY:-1G}"

chown -R redpanda:redpanda "$DATA_DIR" /etc/redpanda

echo "INFO: redpanda advertising ${ADVERTISE_HOST}:29092, memory ${MEMORY}"

exec setpriv --reuid=redpanda --regid=redpanda --init-groups env HOME=/var/lib/redpanda \
  rpk redpanda start \
    --mode dev-container \
    --smp 1 \
    --memory "$MEMORY" \
    --reserve-memory 0M \
    --kafka-addr "PLAINTEXT://[::]:29092" \
    --advertise-kafka-addr "PLAINTEXT://${ADVERTISE_HOST}:29092" \
    --rpc-addr "[::]:33145" \
    --advertise-rpc-addr "${ADVERTISE_HOST}:33145" \
    --pandaproxy-addr "PLAINTEXT://[::]:28082" \
    --schema-registry-addr "[::]:28081"
