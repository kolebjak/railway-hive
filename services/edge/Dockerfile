# Caddy in front of app and server. One public origin keeps Hive's SameSite=Lax
# session cookie first-party, so login works on generated Railway domains, and
# DISABLE_SIGNUP=1 closes email+password registration (no switch in Hive itself,
# see graphql-hive/console#8039).
FROM caddy:2.11.9-alpine

COPY Caddyfile /etc/caddy/Caddyfile

ENV PORT=8080
EXPOSE 8080
