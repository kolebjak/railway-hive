#!/usr/bin/env bash
# Starts the stack from .env (copied from .env.example if missing), waits until
# the console answers, proves the API works, tears everything down.
# KEEP=1 leaves it running. Host ports come from .env (*_HOST_PORT).
set -o errexit -o pipefail -o nounset
cd "$(dirname "$0")"

[[ -f .env ]] || cp .env.example .env
set -o allexport; source .env; set +o allexport

APP="http://localhost:${APP_HOST_PORT:-8080}"
SERVER="http://localhost:${SERVER_HOST_PORT:-8082}"
USAGE="http://localhost:${USAGE_HOST_PORT:-8081}"

fail() { echo "FAIL: $*" >&2; docker compose ps >&2 || true; exit 1; }
cleanup() {
  if [[ "${KEEP:-0}" == "1" ]]; then echo "KEEP=1: stack left running"; return; fi
  docker compose down -v --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT

wait_for() { # url, label
  for _ in $(seq 1 120); do
    curl -fsS -o /dev/null "$1" 2>/dev/null && return 0
    sleep 5
  done
  return 1
}

echo "starting stack (hive@${HIVE_TAG:-14.1.0}) ..."
docker compose up -d --build --quiet-pull

echo "1/4 server ${SERVER}/_health"
wait_for "${SERVER}/_health" || fail "server not healthy after 10 minutes (docker compose logs migrations server)"

echo "2/4 app ${APP}/_health"
wait_for "${APP}/_health" || fail "app not healthy"
code="$(curl -s -o /dev/null -w '%{http_code}' "${APP}/")"
[[ "$code" == "200" ]] || fail "app / returned ${code}"

echo "3/4 usage ${USAGE}/_health"
wait_for "${USAGE}/_health" || fail "usage not healthy (docker compose logs broker usage)"

echo "4/4 graphql on server"
reply="$(curl -fsS "${SERVER}/graphql" -H 'Content-Type: application/json' -d '{"query":"{ __typename }"}')" \
  || fail "graphql request failed"
grep -q '"__typename"' <<<"$reply" || fail "unexpected graphql reply: ${reply:0:300}"

docker compose ps --format '{{.Service}} {{.Status}}' | grep -Ev 'healthy|Exited \(0\)' \
  && fail "some services are not healthy" || true

echo "PASS"
