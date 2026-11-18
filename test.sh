#!/usr/bin/env bash
# Starts the stack from .env (copied from .env.example if missing), then proves
# through the edge: console loads, sign-up, sign-in, session refresh, schema
# publish with a registry token, CDN fetch with a CDN token, a usage report that
# shows up in the target's statistics, and that DISABLE_SIGNUP=1 blocks sign-up
# but not sign-in. Tears everything down. KEEP=1 leaves it running. Host port
# comes from .env (EDGE_HOST_PORT).
set -o errexit -o pipefail -o nounset
cd "$(dirname "$0")"

[[ -f .env ]] || cp .env.example .env
set -o allexport; source .env; set +o allexport

URL="${HIVE_URL:-http://localhost:${EDGE_HOST_PORT:-8080}}"
JAR="$(mktemp)"
EMAIL="e2e-$(date +%s)@example.com"
PASSWORD="e2e-Password-123!"
SLUG="e2e$(date +%s)"

fail() { echo "FAIL: $*" >&2; docker compose ps >&2 || true; exit 1; }
cleanup() {
  rm -f "$JAR"
  if [[ "${KEEP:-0}" == "1" ]]; then echo "KEEP=1: stack left running"; return; fi
  docker compose down -v --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT

wait_for() { # url
  for _ in $(seq 1 120); do
    curl -fsS -o /dev/null "$1" 2>/dev/null && return 0
    sleep 5
  done
  return 1
}

# Session cookies are Secure; curl will not send them over http, so they are
# read from the jar and passed as a header, which is what a browser does on
# localhost.
cookie_header() {
  awk -v n="$1" '$6 == n { printf "%s=%s", $6, $7 }' "$JAR"
}

auth() { # path, json
  curl -fsS "${URL}/auth-api/$1" -H 'Content-Type: application/json' -c "$JAR" -d "$2"
}

gql() { # json query, extra curl args...
  local body="$1"; shift
  curl -fsS "${URL}/graphql" -H 'Content-Type: application/json' "$@" -d "$body"
}

gql_session() { gql "$1" -H "Cookie: $(cookie_header sAccessToken)"; }

json() { python3 -I -c "import sys,json; d=json.load(sys.stdin); print(eval(sys.argv[1]))" "$1"; }

form() { # email, password
  printf '{"formFields":[{"id":"email","value":"%s"},{"id":"password","value":"%s"}]}' "$1" "$2"
}

echo "starting stack (hive@${HIVE_TAG:-14.1.0}) ..."
DISABLE_SIGNUP=0 docker compose up -d --build --quiet-pull

echo "1/10 edge ${URL}/_health, console, graphql"
wait_for "${URL}/_health" || fail "edge not healthy after 10 minutes (docker compose logs migrations server app edge)"
code="$(curl -s -o /dev/null -w '%{http_code}' "${URL}/")"
[[ "$code" == "200" ]] || fail "console / returned ${code}"
grep -q '"__typename"' <<<"$(gql '{"query":"{ __typename }"}')" || fail "graphql through edge failed"

echo "2/10 usage ${URL}/usage/_health"
wait_for "${URL}/usage/_health" || fail "usage not healthy (docker compose logs broker usage)"

echo "3/10 sign-up ${EMAIL}"
reply="$(auth signup "$(form "$EMAIL" "$PASSWORD")")"
grep -q '"status":"OK"' <<<"$reply" || fail "sign-up: ${reply:0:300}"
[[ -n "$(cookie_header sAccessToken)" ]] || fail "sign-up set no sAccessToken cookie"

echo "4/10 session: me, refresh, me again"
me="$(gql_session '{"query":"{ me { id email } }"}')"
grep -q "\"email\":\"${EMAIL}\"" <<<"$me" || fail "me after sign-up: ${me:0:300}"
curl -fsS -o /dev/null "${URL}/auth-api/session/refresh" -X POST -c "$JAR" \
  -H "Cookie: $(cookie_header sRefreshToken)" || fail "session refresh"
me="$(gql_session '{"query":"{ me { id email } }"}')"
grep -q "\"email\":\"${EMAIL}\"" <<<"$me" || fail "me after refresh: ${me:0:300}"

echo "5/10 sign-in"
: > "$JAR"
reply="$(auth signin "$(form "$EMAIL" "$PASSWORD")")"
grep -q '"status":"OK"' <<<"$reply" || fail "sign-in: ${reply:0:300}"

echo "6/10 organization, project, target"
org="$(gql_session "{\"query\":\"mutation { createOrganization(input: { slug: \\\"${SLUG}\\\" }) { ok { createdOrganizationPayload { organization { slug } } } error { message } } }\"}")"
grep -q "\"slug\":\"${SLUG}\"" <<<"$org" || fail "createOrganization: ${org:0:300}"
proj="$(gql_session "{\"query\":\"mutation { createProject(input: { organization: { bySelector: { organizationSlug: \\\"${SLUG}\\\" } }, slug: \\\"api\\\", type: SINGLE }) { ok { createdTargets { id slug } } error { message } } }\"}")"
target_id="$(json "d['data']['createProject']['ok']['createdTargets'][0]['id']" <<<"$proj")" || fail "createProject: ${proj:0:300}"
target_slug="$(json "d['data']['createProject']['ok']['createdTargets'][0]['slug']" <<<"$proj")"

echo "7/10 schema publish with a registry token"
tok="$(gql_session "{\"query\":\"mutation { createToken(input: { organizationSlug: \\\"${SLUG}\\\", projectSlug: \\\"api\\\", targetSlug: \\\"${target_slug}\\\", name: \\\"e2e\\\", organizationScopes: [READ], projectScopes: [READ], targetScopes: [READ, REGISTRY_READ, REGISTRY_WRITE] }) { ok { secret } error { message } } }\"}")"
registry_token="$(json "d['data']['createToken']['ok']['secret']" <<<"$tok")" || fail "createToken: ${tok:0:300}"
pub="$(gql '{"query":"mutation { schemaPublish(input: { sdl: \"type Query { hello: String }\", author: \"e2e\", commit: \"1\" }) { __typename ... on SchemaPublishSuccess { valid } } }"}' \
  -H "Authorization: Bearer ${registry_token}")"
grep -q '"__typename":"SchemaPublishSuccess"' <<<"$pub" || fail "schemaPublish: ${pub:0:300}"

echo "8/10 CDN fetch with a CDN token"
cdn="$(gql_session "{\"query\":\"mutation { createCdnAccessToken(input: { target: { byId: \\\"${target_id}\\\" }, alias: \\\"e2e\\\" }) { ok { secretAccessToken cdnUrl } error { message } } }\"}")"
cdn_key="$(json "d['data']['createCdnAccessToken']['ok']['secretAccessToken']" <<<"$cdn")" || fail "createCdnAccessToken: ${cdn:0:300}"
cdn_url="$(json "d['data']['createCdnAccessToken']['ok']['cdnUrl']" <<<"$cdn")"
[[ "$cdn_url" == "${URL}/"* ]] || fail "cdnUrl ${cdn_url} is not under ${URL} (CDN_API_BASE_URL)"
sdl=""
for _ in $(seq 1 12); do
  sdl="$(curl -sS -L "${cdn_url}/sdl" -H "x-hive-cdn-key: ${cdn_key}")" && grep -q 'hello' <<<"$sdl" && break
  sleep 5
done
grep -q 'hello' <<<"$sdl" || fail "CDN sdl: ${sdl:0:300}"

echo "9/10 usage report through ${URL}/usage, then visible in operationsStats"
now_ms="$(( $(date +%s) * 1000 ))"
report="$(printf '{"size":1,"map":{"k1":{"operationName":"hello","operation":"query hello { hello }","fields":["Query","Query.hello"]}},"operations":[{"operationMapKey":"k1","timestamp":%s,"execution":{"ok":true,"duration":1000000,"errorsTotal":0}}]}' "$now_ms")"
code="$(curl -s -o /dev/null -w '%{http_code}' "${URL}/usage" -H 'Content-Type: application/json' -H 'X-Usage-API-Version: 2' \
  -H "Authorization: Bearer ${registry_token}" -d "$report")"
[[ "$code" == "200" ]] || fail "usage report returned ${code}"
from="$(date -u -v-1d +%Y-%m-%dT%H:%M:%S.000Z 2>/dev/null || date -u -d '1 day ago' +%Y-%m-%dT%H:%M:%S.000Z)"
to="$(date -u -v+1d +%Y-%m-%dT%H:%M:%S.000Z 2>/dev/null || date -u -d '1 day' +%Y-%m-%dT%H:%M:%S.000Z)"
total=0
for _ in $(seq 1 36); do
  stats="$(gql_session "{\"query\":\"{ target(reference: { byId: \\\"${target_id}\\\" }) { operationsStats(period: { from: \\\"${from}\\\", to: \\\"${to}\\\" }) { totalRequests } } }\"}")"
  total="$(json "d['data']['target']['operationsStats']['totalRequests']" <<<"$stats" 2>/dev/null || echo 0)"
  [[ "$total" != "0" && "$total" != "None" ]] && break
  sleep 5
done
[[ "$total" != "0" && "$total" != "None" ]] || fail "usage report not ingested after 3 minutes: ${stats:0:300} (docker compose logs usage usage-ingestor)"

echo "10/10 DISABLE_SIGNUP=1 blocks sign-up, sign-in still works"
DISABLE_SIGNUP=1 docker compose up -d --no-deps edge >/dev/null
wait_for "${URL}/_health" || fail "edge did not come back"
code="$(curl -s -o /dev/null -w '%{http_code}' "${URL}/auth-api/signup" -H 'Content-Type: application/json' -d "$(form "other-${EMAIL}" "$PASSWORD")")"
[[ "$code" == "403" ]] || fail "sign-up with DISABLE_SIGNUP=1 returned ${code}, expected 403"
: > "$JAR"
reply="$(auth signin "$(form "$EMAIL" "$PASSWORD")")"
grep -q '"status":"OK"' <<<"$reply" || fail "sign-in with DISABLE_SIGNUP=1: ${reply:0:300}"
DISABLE_SIGNUP=0 docker compose up -d --no-deps edge >/dev/null

for _ in $(seq 1 12); do
  unhealthy="$(docker compose ps --format '{{.Service}} {{.Status}}' | grep -Ev '\(healthy\)|Exited \(0\)' || true)"
  [[ -z "$unhealthy" ]] && break
  sleep 5
done
[[ -z "$unhealthy" ]] || fail "some services are not healthy: ${unhealthy}"

echo "PASS"
