# GraphQL Hive Console on Railway

Self-hosted [GraphQL Hive](https://the-guild.dev/graphql/hive) Console — schema
registry, schema checks and field-level usage analytics — as one Railway template,
pinned to **hive@14.1.0**. One click, zero required inputs.

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/lDR_SU)

> **After the first sign-up, set `DISABLE_SIGNUP=1` on `edge`.** Hive has no
> sign-up switch of its own and no instance owner: anyone who can open the console
> can create an account and an organization. See [Closing sign-up](#closing-sign-up).


## What you get

Fourteen services: the set from Hive's
[community compose file](https://github.com/graphql-hive/console/blob/hive%4014.1.0/docker/docker-compose.community.yml),
one container per Railway service wired over the private network, plus `edge`.

| Service | Image | Public | Role |
| --- | --- | --- | --- |
| `edge` | [`services/edge`](services/edge) (Caddy) | **yes** | The one public domain: console, API, CDN, `/usage`; sign-up switch |
| `app` | `ghcr.io/graphql-hive/app:14.1.0` | no | Console UI |
| `server` | [`services/server`](services/server) | no | GraphQL API, CDN artifacts (`/artifacts/v1/…`) |
| `usage` | `ghcr.io/graphql-hive/usage:14.1.0` | no | Usage-report ingestion from gateways and SDKs |
| `usage-ingestor` | `ghcr.io/graphql-hive/usage-ingestor:14.1.0` | no | Kafka → ClickHouse |
| `schema` | `ghcr.io/graphql-hive/schema:14.1.0` | no | Composition and validation |
| `policy` | `ghcr.io/graphql-hive/policy:14.1.0` | no | Schema policy (linting) |
| `workflows` | `ghcr.io/graphql-hive/workflows:14.1.0` | no | Emails, alerts, background jobs |
| `migrations` | `ghcr.io/graphql-hive/storage:14.1.0` | no | One-shot Postgres + ClickHouse migrations |
| `db` | `postgres:16.4-alpine` | no | Registry data |
| `clickhouse` | `clickhouse/clickhouse-server:26.3.12.3-alpine` | no | Usage analytics |
| `broker` | [`services/broker`](services/broker) (Redpanda) | no | Kafka API for usage reports |
| `redis` | [`services/redis`](services/redis) | no | Cache, queues |
| `s3` | [`services/s3`](services/s3) (versitygw) | no | Schema artifacts, audit logs |

Only `app`, `server` and `usage` get a public domain. Everything else is reachable
only inside the project.

The four wrapper images exist because Railway cannot run a compose file:

- **server** — generates the RS256 key behind `SUPERTOKENS_ACCESS_TOKEN_KEY` on
  first boot and keeps it in a volume. Every other secret is a random string the
  template generates; this one is an RSA key pair, which `${{secret()}}` cannot make.
- **broker** — single-node Redpanda that binds IPv6 (Railway's private network) and
  advertises its own private domain. Upstream's command points at a seed node that
  does not exist in a single-node setup.
- **s3** — versitygw with bucket root and posix metadata under one mount, because a
  Railway service has exactly one volume.
- **redis** — Bitnami Redis started as root so it can own a Railway volume; its own
  entrypoint drops privileges.
- **edge** — Caddy. Routes `/graphql`, `/graphql-public`, `/auth-api/*`,
  `/artifacts/*` and `/scim/*` to `server`, `/usage` and `/usage/*` (prefix
  stripped) to `usage`, everything else to `app`. Same layout as Hive Cloud, where
  reports go to `app.graphql-hive.com/usage`; `usage` is a reserved organization
  slug in Hive, so the prefix cannot collide with a console URL. Hive's server
  sets its session cookies `SameSite=Lax` and reads them only from cookies
  ([`supertokens-at-home.ts`](https://github.com/graphql-hive/console/blob/hive%4014.1.0/packages/services/server/src/supertokens-at-home.ts)),
  so console and API must share an origin or the browser never sends the cookie
  (`up.railway.app` is a public suffix, so two generated domains are two sites).
  One host also carries the sign-up switch.

Not included: Hive's `s3_reverse_proxy` (nothing in 14.1.0 reads it) and the
High-Availability CDN (not available when self-hosting; `server` serves artifacts).

## Inputs

None required. Optional, all on the service named:

| Service | Variable | Default | What it does |
| --- | --- | --- | --- |
| `workflows` | `EMAIL_PROVIDER` | `mock` | `mock` logs emails. `smtp` or `postmark` sends them; see below. `sendmail` needs an MTA the image does not have. |
| `workflows` | `EMAIL_FROM` | `no-reply@example.com` | Sender address. |
| `workflows` | `EMAIL_PROVIDER_SMTP_HOST` / `_PORT` / `_AUTH_USERNAME` / `_AUTH_PASSWORD` | — | Required when `EMAIL_PROVIDER=smtp`. Optional `_PROTOCOL` (`smtp`/`smtps`), `_REJECT_UNAUTHORIZED`, `_IGNORE_TLS`. |
| `workflows` | `EMAIL_PROVIDER_POSTMARK_TOKEN` / `_MESSAGE_STREAM` | — | Required when `EMAIL_PROVIDER=postmark`. |
| `migrations` | `CLICKHOUSE_TTL_TABLES`, `_DAILY_MV_TABLES`, `_HOURLY_MV_TABLES`, `_MINUTELY_MV_TABLES` | unset | Usage retention, e.g. `1 YEAR`, `30 DAY`. Unset keeps Hive's default (organizations limited to 7 days). Redeploy `migrations` after changing. |
| `edge` | `DISABLE_SIGNUP` | `0` | `1` answers `POST /auth-api/signup` with 403. See [Closing sign-up](#closing-sign-up). |
| `broker` | `REDPANDA_MEMORY` | `1G` | Memory Redpanda reserves at start. |
| `server`, `app` | `AUTH_REQUIRE_EMAIL_VERIFICATION` | `0` | Set `1` once email sending works. |
| `server` | `AUTH_GITHUB*`, `AUTH_GOOGLE*`, `AUTH_OKTA*` | unset | Social login; see Hive's [server README](https://github.com/graphql-hive/console/tree/hive%4014.1.0/packages/services/server). |
| any Hive service | `LOG_LEVEL` | `info` | `trace` … `silent`. |

Email verification is off by default so sign-up works before email is configured.

## Outputs

One domain, that of `edge`:

| Endpoint | URL | Used by |
| --- | --- | --- |
| Console | `https://<edge domain>/` | people |
| Registry API | `https://<edge domain>/graphql` | Hive CLI, SDKs |
| CDN | `https://<edge domain>/artifacts/v1/<target-id>` | gateways |
| Usage | `https://<edge domain>/usage` | gateways and SDKs reporting usage |

## Closing sign-up

Hive 14.1.0 cannot disable registration
([graphql-hive/console#8039](https://github.com/graphql-hive/console/issues/8039),
open). Every sign-up creates a user and their own organization; there is no
instance owner. So: deploy, sign up, then set `DISABLE_SIGNUP=1` on `edge`
(Variables → redeploy). From then on:

| Request | Result |
| --- | --- |
| `POST /auth-api/signup` (email + password registration, including people you invited who have no account yet) | **403** from Caddy |
| `POST /auth-api/signin`, session refresh, password reset | unchanged |
| `POST /auth-api/signinup` (GitHub, Google, Okta or organization OIDC, when configured) | unchanged: a first social/OIDC login still creates the account |

To onboard someone by email, set `DISABLE_SIGNUP=0`, let them register, set it
back. Invitations to an organization are a separate step inside Hive.

## Custom domains (optional)

The generated `edge-….up.railway.app` domain is enough for login. To use your own
domain, add it to `edge` under **Settings → Networking → Custom Domain**, create the
`CNAME` **and** `TXT` records Railway shows, then set these variables by hand and
redeploy `server`, `workflows`, `app`.
Railway documents `RAILWAY_PUBLIC_DOMAIN` as the generated host and does not say it
follows a custom domain, so do not rely on the template's reference values.

| Service | Variable | Value |
| --- | --- | --- |
| `server` | `GRAPHQL_PUBLIC_ORIGIN`, `CDN_API_BASE_URL`, `WEB_APP_URL` | `https://hive.example.com` |
| `workflows` | `WEB_APP_URL` | `https://hive.example.com` |
| `app` | `APP_BASE_URL`, `GRAPHQL_PUBLIC_ORIGIN` | `https://hive.example.com` |
| `app` | `GRAPHQL_PUBLIC_ENDPOINT`, `GRAPHQL_PUBLIC_SUBSCRIPTION_ENDPOINT` | `https://hive.example.com/graphql` |

### Using it from a project

1. Open the console, sign up, create an **organization**, a **project** (type
   Single or Federation) and a **target** per environment (e.g. `staging`,
   `production`). Then close sign-up (above).
2. Target → **Settings → Registry Access Tokens** → create a token with
   **schema:publish** (registry write) and **usage:report**. This is `HIVE_TOKEN`.
3. Target → **Settings → CDN Access** → create a token. This is `HIVE_CDN_KEY`;
   the CDN endpoint for the target is shown next to it.

Then, wherever your CI and gateway run:

| Value | Where it comes from |
| --- | --- |
| `HIVE_CDN_URL` | `https://<edge domain>/artifacts/v1/<target-id>` (copy from CDN Access) |
| `HIVE_CDN_KEY` | CDN token, step 3 |
| `HIVE_TOKEN` | registry token, step 2 |
| `HIVE_USAGE_URL` | `https://<edge domain>/usage` |

Hive CLI (`hive.json` or flags):

```json
{ "registry": { "endpoint": "https://<edge domain>/graphql", "accessToken": "<HIVE_TOKEN>" } }
```

Hive Gateway (`gateway.config.ts`):

```ts
import { defineConfig } from '@graphql-hive/gateway';

export const gatewayConfig = defineConfig({
  supergraph: { type: 'hive', endpoint: process.env.HIVE_CDN_URL, key: process.env.HIVE_CDN_KEY },
  reporting: {
    type: 'hive',
    token: process.env.HIVE_TOKEN,
    target: '<org>/<project>/<target>',
    selfHosting: {
      graphqlEndpoint: 'https://<edge domain>/graphql',
      applicationUrl: 'https://<edge domain>',
      usageEndpoint: process.env.HIVE_USAGE_URL,
    },
  },
});
```

The same `selfHosting` block applies to `@graphql-hive/yoga`, `@graphql-hive/apollo`
and `@graphql-hive/envelop`.

### Bring your own gateway

This template is the console only. A gateway belongs in the Railway project of the
API it fronts — Railway private networking does not cross projects — and talks to
this console over the public `edge` domain. See the
[Hive Gateway docs](https://the-guild.dev/graphql/hive/docs/gateway).

## Operations

**Upgrade.** Everything is pinned to one Hive release (`edge` separately to a
Caddy release in `services/edge/Dockerfile`). To move to `hive@X.Y.Z`:
bump the tag in `services/server/Dockerfile`, `.env.example` (`HIVE_TAG`),
`.github/workflows/publish-image.yml`, every `ghcr.io/graphql-hive/*` image in the
template and in `docker-compose.yml`; diff upstream's compose file at the new tag
for new variables or services; run `./test.sh`; redeploy `migrations` first, then
the rest. Read the
[self-hosting changelog](https://the-guild.dev/graphql/hive/docs/schema-registry/self-hosting/changelog)
for breaking changes. Never regenerate secrets on upgrade — data was encrypted with them.

**Backups.** Enable Railway volume backups on `db` (registry, users, tokens) and
`clickhouse` (usage history). `s3` holds artifacts that `schema:publish` recreates;
`broker` and `redis` are transient. The `server` volume holds the session signing
key; losing it only logs everyone out.

**Migrations on redeploy.** `migrations` exits 0 and stays "completed". Redeploy it
after every upgrade and after changing a `CLICKHOUSE_TTL_*` value. `server` restarts
until migrations have run, so a fresh deploy may show a few restarts.

**Sizing.** Measured at idle on the local stack: server ~640 MB, schema ~380 MB,
clickhouse ~370 MB, broker ~350 MB, the rest under 200 MB each.

## Local development

```bash
cp .env.example .env     # edit EDGE_HOST_PORT + HIVE_URL if 8080 is taken
./test.sh                # builds, boots, checks, tears down; KEEP=1 to keep it up
```

`test.sh` goes through `edge` like a browser would: console loads, sign-up,
sign-in, session refresh, organization + project, schema publish with a registry
token, CDN fetch with a CDN token, a usage report to `/usage` that shows up in
the target's statistics, then restarts `edge` with `DISABLE_SIGNUP=1` and checks
sign-up is 403 while sign-in still works. The compose network is
dual-stack so the IPv6 path Railway uses is exercised too. With `KEEP=1` the
console is at `http://localhost:8080`.

## License

MIT
