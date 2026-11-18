# Publishing this as a Railway template

Everything below is done once in the template composer. Service **names are
fixed**: every reference variable (`${{db.RAILWAY_PRIVATE_DOMAIN}}`,
`${{server.ENCRYPTION_SECRET}}`) is built from them. Use the composer's
reference-variable picker rather than typing the literal string where you can.

`railway.json` in each wrapper directory carries build, healthcheck and restart
settings for repo-based deploys, but Railway has deprecated config-as-code (files
stop being read on 2026-12-01), so **set healthcheck path and restart policy in the
composer** as listed here; that is what the template records.

## 0. Before the composer

1. Push this repo to GitHub. `.github/workflows/publish-image.yml` builds the four
   wrapper images for amd64 + arm64 and pushes them to
   `ghcr.io/kolebjak/railway-hive-{server,broker,s3,redis}:14.1.0`.
2. Make those four GHCR packages **public** (repo → Packages → package settings).
   Deploying images rather than the repo means template users need no GitHub
   connection, spend no build minutes, and run the bytes `test.sh` tested.
   Alternative for any wrapper: source = this repo, **Root Directory**
   `services/<name>` (the user's Railway then needs the repo connection).

## 1. Composer

[railway.com/templates](https://railway.com/templates) → **New Template**. Add the
14 services below, in this order (references resolve regardless, but each step only
references services already added). Restart policy: **Always** everywhere except
`migrations` (**Never**). Public networking: only `edge`; `app`, `server` and
`usage` are reached through it.

Service icons (click the cube next to the service name, type a value, press
Enter; the composer accepts a [devicons](https://devicons.railway.app) slug or
any image URL):

| Service | Icon |
| --- | --- |
| `db` | `postgres` |
| `clickhouse` | `clickhouse` |
| `redis` | `redis` |
| `broker` | `https://cdn.simpleicons.org/apachekafka/white` |
| `s3` | `aws` |
| `edge` | `https://cdn.simpleicons.org/caddy` |
| all Hive services | `https://raw.githubusercontent.com/graphql-hive/console/main/packages/web/app/public/just-logo.svg` |

Secret shorthands used below:

| Shorthand | Composer value | Equivalent |
| --- | --- | --- |
| `SECRET` | `${{secret()}}` | 32-char random password |
| `HEX32` | `${{secret(32, "abcdef0123456789")}}` | `openssl rand -hex 16` |
| `HEX64` | `${{secret(64, "abcdef0123456789")}}` | `openssl rand -hex 32` |
| `HEX128` | `${{secret(128, "abcdef0123456789")}}` | `openssl rand -hex 64` |

### 1. `db`

| Setting | Value |
| --- | --- |
| Source | image `postgres:16.4-alpine` |
| Volume | `/var/lib/postgresql/data` |
| Healthcheck | none (not HTTP) |

| Variable | Value |
| --- | --- |
| `POSTGRES_DB` | `registry` |
| `POSTGRES_USER` | `hive` |
| `POSTGRES_PASSWORD` | `SECRET` |
| `PGDATA` | `/var/lib/postgresql/data/pgdata` (volume root has `lost+found`, which initdb rejects) |

### 2. `clickhouse`

| Setting | Value |
| --- | --- |
| Source | image `clickhouse/clickhouse-server:26.3.12.3-alpine` |
| Volume | `/var/lib/clickhouse` |
| Healthcheck | `/ping` |

| Variable | Value |
| --- | --- |
| `CLICKHOUSE_USER` | `hive` |
| `CLICKHOUSE_PASSWORD` | `SECRET` |
| `PORT` | `8123` (healthcheck target) |

### 3. `redis`

| Setting | Value |
| --- | --- |
| Source | image `ghcr.io/kolebjak/railway-hive-redis:14.1.0` |
| Volume | `/bitnami/redis/data` |
| Healthcheck | none |

| Variable | Value |
| --- | --- |
| `REDIS_PASSWORD` | `SECRET` |
| `REDIS_DISABLE_COMMANDS` | `FLUSHDB,FLUSHALL` |

### 4. `broker`

| Setting | Value |
| --- | --- |
| Source | image `ghcr.io/kolebjak/railway-hive-broker:14.1.0` |
| Volume | `/var/lib/redpanda/data` |
| Healthcheck | none (admin API is IPv4 loopback only) |

| Variable | Value |
| --- | --- |
| `REDPANDA_MEMORY` | `1G` (optional) |

The entrypoint advertises `${{RAILWAY_PRIVATE_DOMAIN}}` by itself; nothing to set.

### 5. `s3`

| Setting | Value |
| --- | --- |
| Source | image `ghcr.io/kolebjak/railway-hive-s3:14.1.0` |
| Volume | `/srv` |
| Healthcheck | `/minio/health/live` |

| Variable | Value |
| --- | --- |
| `ROOT_ACCESS_KEY` | `hive` |
| `ROOT_SECRET_KEY` | `SECRET` |
| `PORT` | `9000` |

### 6. `migrations`

| Setting | Value |
| --- | --- |
| Source | image `ghcr.io/graphql-hive/storage:14.1.0` |
| Restart policy | **Never** — exits 0 when done |
| Healthcheck | none |

| Variable | Value |
| --- | --- |
| `MIGRATOR` | `up` |
| `CLICKHOUSE_MIGRATOR` | `up` |
| `POSTGRES_HOST` | `${{db.RAILWAY_PRIVATE_DOMAIN}}` |
| `POSTGRES_PORT` | `5432` |
| `POSTGRES_DB` | `${{db.POSTGRES_DB}}` |
| `POSTGRES_USER` | `${{db.POSTGRES_USER}}` |
| `POSTGRES_PASSWORD` | `${{db.POSTGRES_PASSWORD}}` |
| `REDIS_HOST` | `${{redis.RAILWAY_PRIVATE_DOMAIN}}` |
| `REDIS_PORT` | `6379` |
| `REDIS_PASSWORD` | `${{redis.REDIS_PASSWORD}}` |
| `CLICKHOUSE_PROTOCOL` | `http` |
| `CLICKHOUSE_HOST` | `${{clickhouse.RAILWAY_PRIVATE_DOMAIN}}` |
| `CLICKHOUSE_PORT` | `8123` |
| `CLICKHOUSE_USERNAME` | `${{clickhouse.CLICKHOUSE_USER}}` |
| `CLICKHOUSE_PASSWORD` | `${{clickhouse.CLICKHOUSE_PASSWORD}}` |
| `CLICKHOUSE_TTL_TABLES` | empty, optional (e.g. `1 YEAR`) |
| `CLICKHOUSE_TTL_DAILY_MV_TABLES` | empty, optional |
| `CLICKHOUSE_TTL_HOURLY_MV_TABLES` | empty, optional |
| `CLICKHOUSE_TTL_MINUTELY_MV_TABLES` | empty, optional |
| `TS_NODE_TRANSPILE_ONLY` | `true` |
| `LOG_LEVEL` | `info` |

### 7. `server`

| Setting | Value |
| --- | --- |
| Source | image `ghcr.io/kolebjak/railway-hive-server:14.1.0` |
| Volume | `/keys` (holds the generated RS256 session key) |
| Public networking | none (reached through `edge`) |
| Healthcheck | `/_health` |

| Variable | Value |
| --- | --- |
| `PORT` | `3001` |
| `NODE_ENV` | `production` |
| `ENCRYPTION_SECRET` | `HEX32` |
| `CDN_AUTH_PRIVATE_KEY` | `HEX64` |
| `SUPERTOKENS_REFRESH_TOKEN_KEY` | `1000:HEX128:HEX128` — literally `1000:${{secret(128, "abcdef0123456789")}}:${{secret(128, "abcdef0123456789")}}` |
| `SUPERTOKENS_ACCESS_TOKEN_KEY` | leave **unset** — generated on first boot into `/keys` (see below) |
| `CDN_API` | `1` |
| `CDN_API_BASE_URL` | `https://${{edge.RAILWAY_PUBLIC_DOMAIN}}` (add `edge` first or fill in after step 14) |
| `GRAPHQL_PUBLIC_ORIGIN` | `https://${{edge.RAILWAY_PUBLIC_DOMAIN}}` |
| `WEB_APP_URL` | `https://${{edge.RAILWAY_PUBLIC_DOMAIN}}` |
| `SUPERTOKENS_RATE_LIMIT_IP_HEADER_NAME` | `X-Real-IP` — Railway's edge sets it, Caddy passes it through; without it the auth rate limiter keys on Caddy's address, one bucket for everyone |
| `AUTH_ORGANIZATION_OIDC` | `1` |
| `AUTH_REQUIRE_EMAIL_VERIFICATION` | `0` |
| `POSTGRES_HOST` | `${{db.RAILWAY_PRIVATE_DOMAIN}}` |
| `POSTGRES_PORT` | `5432` |
| `POSTGRES_DB` | `${{db.POSTGRES_DB}}` |
| `POSTGRES_USER` | `${{db.POSTGRES_USER}}` |
| `POSTGRES_PASSWORD` | `${{db.POSTGRES_PASSWORD}}` |
| `CLICKHOUSE_PROTOCOL` | `http` |
| `CLICKHOUSE_HOST` | `${{clickhouse.RAILWAY_PRIVATE_DOMAIN}}` |
| `CLICKHOUSE_PORT` | `8123` |
| `CLICKHOUSE_USERNAME` | `${{clickhouse.CLICKHOUSE_USER}}` |
| `CLICKHOUSE_PASSWORD` | `${{clickhouse.CLICKHOUSE_PASSWORD}}` |
| `REDIS_HOST` | `${{redis.RAILWAY_PRIVATE_DOMAIN}}` |
| `REDIS_PORT` | `6379` |
| `REDIS_PASSWORD` | `${{redis.REDIS_PASSWORD}}` |
| `S3_ENDPOINT` | `http://${{s3.RAILWAY_PRIVATE_DOMAIN}}:9000` |
| `S3_ACCESS_KEY_ID` | `${{s3.ROOT_ACCESS_KEY}}` |
| `S3_SECRET_ACCESS_KEY` | `${{s3.ROOT_SECRET_KEY}}` |
| `S3_BUCKET_NAME` | `artifacts` |
| `S3_AUDIT_LOG_ENDPOINT` | `http://${{s3.RAILWAY_PRIVATE_DOMAIN}}:9000` |
| `S3_AUDIT_LOG_ACCESS_KEY_ID` | `${{s3.ROOT_ACCESS_KEY}}` |
| `S3_AUDIT_LOG_SECRET_ACCESS_KEY` | `${{s3.ROOT_SECRET_KEY}}` |
| `S3_AUDIT_LOG_BUCKET_NAME` | `audit-logs` |
| `SCHEMA_ENDPOINT` | `http://${{schema.RAILWAY_PRIVATE_DOMAIN}}:3002` |
| `SCHEMA_POLICY_ENDPOINT` | `http://${{policy.RAILWAY_PRIVATE_DOMAIN}}:3012` |
| `LOG_LEVEL` | `info` |

**Why the key is generated in the container.** `SUPERTOKENS_ACCESS_TOKEN_KEY` is an
RSA key pair (`<id>|<public>|<private>`), the one value `${{secret()}}` cannot
produce; a documented "generate it and paste it" step would make every deploy
manual and leave the private key visible in the composer. The wrapper generates it
with `openssl` on first boot, stores it in the `/keys` volume so sessions survive
redeploys, and still honours an explicit `SUPERTOKENS_ACCESS_TOKEN_KEY` if one is set
(e.g. when migrating an existing instance).

### 8. `schema`

| Setting | Value |
| --- | --- |
| Source | image `ghcr.io/graphql-hive/schema:14.1.0` |
| Healthcheck | `/_health` |

| Variable | Value |
| --- | --- |
| `PORT` | `3002` |
| `NODE_ENV` | `production` |
| `ENCRYPTION_SECRET` | `${{server.ENCRYPTION_SECRET}}` |
| `REDIS_HOST` | `${{redis.RAILWAY_PRIVATE_DOMAIN}}` |
| `REDIS_PORT` | `6379` |
| `REDIS_PASSWORD` | `${{redis.REDIS_PASSWORD}}` |
| `LOG_LEVEL` | `info` |

### 9. `policy`

| Setting | Value |
| --- | --- |
| Source | image `ghcr.io/graphql-hive/policy:14.1.0` |
| Healthcheck | `/_health` |

| Variable | Value |
| --- | --- |
| `PORT` | `3012` |
| `NODE_ENV` | `production` |
| `LOG_LEVEL` | `info` |

### 10. `workflows`

| Setting | Value |
| --- | --- |
| Source | image `ghcr.io/graphql-hive/workflows:14.1.0` |
| Healthcheck | `/_health` |

| Variable | Value |
| --- | --- |
| `PORT` | `3014` |
| `NODE_ENV` | `production` |
| `EMAIL_PROVIDER` | `mock` — mark optional; `smtp` / `postmark` need the vars in README |
| `EMAIL_FROM` | `no-reply@example.com` — mark optional |
| `ENCRYPTION_SECRET` | `${{server.ENCRYPTION_SECRET}}` |
| `WEB_APP_URL` | `https://${{edge.RAILWAY_PUBLIC_DOMAIN}}` |
| `SCHEMA_ENDPOINT` | `http://${{schema.RAILWAY_PRIVATE_DOMAIN}}:3002` |
| `POSTGRES_HOST` | `${{db.RAILWAY_PRIVATE_DOMAIN}}` |
| `POSTGRES_PORT` | `5432` |
| `POSTGRES_DB` | `${{db.POSTGRES_DB}}` |
| `POSTGRES_USER` | `${{db.POSTGRES_USER}}` |
| `POSTGRES_PASSWORD` | `${{db.POSTGRES_PASSWORD}}` |
| `REDIS_HOST` | `${{redis.RAILWAY_PRIVATE_DOMAIN}}` |
| `REDIS_PORT` | `6379` |
| `REDIS_PASSWORD` | `${{redis.REDIS_PASSWORD}}` |
| `LOG_JSON` | `1` |
| `LOG_LEVEL` | `info` |

### 11. `usage`

| Setting | Value |
| --- | --- |
| Source | image `ghcr.io/graphql-hive/usage:14.1.0` |
| Public networking | none (reached through `edge` at `/usage`) |
| Healthcheck | `/_health` |

| Variable | Value |
| --- | --- |
| `PORT` | `3006` |
| `NODE_ENV` | `production` |
| `KAFKA_CONNECTION_MODE` | `docker` |
| `KAFKA_BROKER` | `${{broker.RAILWAY_PRIVATE_DOMAIN}}:29092` |
| `KAFKA_TOPIC` | `usage_reports_v2` |
| `KAFKA_BUFFER_SIZE` | `350` |
| `KAFKA_BUFFER_INTERVAL` | `1000` |
| `KAFKA_BUFFER_DYNAMIC` | `1` |
| `POSTGRES_HOST` | `${{db.RAILWAY_PRIVATE_DOMAIN}}` |
| `POSTGRES_PORT` | `5432` |
| `POSTGRES_DB` | `${{db.POSTGRES_DB}}` |
| `POSTGRES_USER` | `${{db.POSTGRES_USER}}` |
| `POSTGRES_PASSWORD` | `${{db.POSTGRES_PASSWORD}}` |
| `REDIS_HOST` | `${{redis.RAILWAY_PRIVATE_DOMAIN}}` |
| `REDIS_PORT` | `6379` |
| `REDIS_PASSWORD` | `${{redis.REDIS_PASSWORD}}` |
| `LOG_LEVEL` | `info` |

### 12. `usage-ingestor`

| Setting | Value |
| --- | --- |
| Source | image `ghcr.io/graphql-hive/usage-ingestor:14.1.0` |
| Healthcheck | `/_health` |

| Variable | Value |
| --- | --- |
| `PORT` | `3007` |
| `NODE_ENV` | `production` |
| `KAFKA_CONNECTION_MODE` | `docker` |
| `KAFKA_BROKER` | `${{broker.RAILWAY_PRIVATE_DOMAIN}}:29092` |
| `KAFKA_TOPIC` | `usage_reports_v2` |
| `KAFKA_CONSUMER_GROUP` | `usage-ingestor-v2` |
| `KAFKA_CONCURRENCY` | `1` |
| `CLICKHOUSE_PROTOCOL` | `http` |
| `CLICKHOUSE_HOST` | `${{clickhouse.RAILWAY_PRIVATE_DOMAIN}}` |
| `CLICKHOUSE_PORT` | `8123` |
| `CLICKHOUSE_USERNAME` | `${{clickhouse.CLICKHOUSE_USER}}` |
| `CLICKHOUSE_PASSWORD` | `${{clickhouse.CLICKHOUSE_PASSWORD}}` |
| `LOG_LEVEL` | `info` |

### 13. `app`

| Setting | Value |
| --- | --- |
| Source | image `ghcr.io/graphql-hive/app:14.1.0` |
| Public networking | none (reached through `edge`) |
| Healthcheck | `/_health` |

| Variable | Value |
| --- | --- |
| `PORT` | `3000` |
| `NODE_ENV` | `production` |
| `APP_BASE_URL` | `https://${{edge.RAILWAY_PUBLIC_DOMAIN}}` |
| `GRAPHQL_PUBLIC_ENDPOINT` | `https://${{edge.RAILWAY_PUBLIC_DOMAIN}}/graphql` |
| `GRAPHQL_PUBLIC_SUBSCRIPTION_ENDPOINT` | `https://${{edge.RAILWAY_PUBLIC_DOMAIN}}/graphql` |
| `GRAPHQL_PUBLIC_ORIGIN` | `https://${{edge.RAILWAY_PUBLIC_DOMAIN}}` |
| `AUTH_REQUIRE_EMAIL_VERIFICATION` | `0` |
| `AUTH_ORGANIZATION_OIDC` | `1` |
| `LOG_LEVEL` | `info` |

### 14. `edge`

| Setting | Value |
| --- | --- |
| Source | image `ghcr.io/kolebjak/railway-hive-edge:14.1.0` |
| Public networking | **HTTP, target port 8080** |
| Healthcheck | `/_health` (answered by Caddy itself) |

| Variable | Value |
| --- | --- |
| `PORT` | `8080` |
| `APP_UPSTREAM` | `${{app.RAILWAY_PRIVATE_DOMAIN}}:3000` |
| `SERVER_UPSTREAM` | `${{server.RAILWAY_PRIVATE_DOMAIN}}:3001` |
| `USAGE_UPSTREAM` | `${{usage.RAILWAY_PRIVATE_DOMAIN}}:3006` |
| `DISABLE_SIGNUP` | `0` — mark optional; description: `1 blocks email+password sign-up (403). Set after your first account exists.` |

Now go back to `server` and `workflows` and confirm every `edge.RAILWAY_PUBLIC_DOMAIN`
reference resolves. All public URLs point at `edge`: the SameSite=Lax session
cookie is first-party, login works on the generated domain, and usage reports go
to `https://<edge domain>/usage` (Caddy strips the prefix).

## Template page text

Paste this at the top of the template **Overview** (Marketplace tab), right under
the H1:

```
> **After your first sign-up, set `DISABLE_SIGNUP=1` on the `edge` service** and
> redeploy it. Hive has no sign-up switch and no instance owner: anyone who can
> open the console can register and create an organization
> (graphql-hive/console#8039). The switch returns 403 for email+password
> registration; sign-in, password reset and social/OIDC login are unaffected.
> Details: https://github.com/kolebjak/railway-hive#closing-sign-up
```

Remove the earlier "Login needs custom domains" paragraph: with `edge` the console
and the API share one origin and login works on `*.up.railway.app`.

## 2. Publish

1. **Publish** the template. Deploy it once into a scratch project and check:
   `migrations` ends as completed, `https://<edge domain>/_health` and
   `/usage/_health` are 200, `/` shows the console and `/graphql` answers.
2. On the generated `edge` domain, in Safari or Firefox **and** in Chrome: sign up,
   reload, the session must survive (no `UNAUTHENTICATED` on
   `myDefaultOrganization`). Set `DISABLE_SIGNUP=1` on `edge`, redeploy it: sign-up
   must show an error, sign-in must still work.
3. Deploy button in `README.md` points at `https://railway.com/deploy/lDR_SU` (template `lDR_SU`, composer id `157b289d-c13d-437b-99c2-484c84f603d7`).

## Start order on a fresh deploy

Railway starts all 14 at once. `migrations` needs `db`, `clickhouse`, `redis`;
`server`, `workflows`, `usage`, `usage-ingestor` need the migrations to have
finished and crash until then. With restart policy **Always** they settle within a
couple of minutes; the Hive services are the ones to watch. `edge` and `app` are
healthy immediately, but the console only works once `server` is up (502 from
`edge` until then).

## Upgrading the template

Compose file, wrapper Dockerfiles and composer images move together. For
`hive@X.Y.Z`: bump `services/server/Dockerfile`, `HIVE_TAG` in `.env.example` and
`.github/workflows/publish-image.yml`, the `ghcr.io/graphql-hive/*` tags in
`docker-compose.yml`; diff upstream's `docker/docker-compose.community.yml` at the new
tag against ours for new services or variables; `./test.sh`; push (images rebuild);
edit the template's image tags in the composer; publish the new version. Users then
get Railway's template-update notification. `edge` is pinned to a Caddy release in
`services/edge/Dockerfile`, independent of the Hive version.

## Moving the published template to `edge`

Done on 2026-11-18 for template `lDR_SU`: `edge` added (step 14), public domains
removed from `app`, `server` and `usage`, all URL references repointed to
`edge.RAILWAY_PUBLIC_DOMAIN`, `SUPERTOKENS_RATE_LIMIT_IP_HEADER_NAME` added on
`server`, overview replaced. Existing deployments are not changed by a template
update; they keep working on custom domains. Gateways that report to an old
`usage` domain must move to `https://<edge domain>/usage`.
