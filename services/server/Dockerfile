# Hive `server` (GraphQL API + CDN artifacts) with one addition: the RS256 key
# behind SUPERTOKENS_ACCESS_TOKEN_KEY is generated on first boot and kept in a
# volume, because Railway's ${{secret()}} can only produce random strings.
FROM ghcr.io/graphql-hive/server:14.1.0

COPY entrypoint.sh /railway_entrypoint.sh
RUN chmod +x /railway_entrypoint.sh

ENV PORT=3001
EXPOSE 3001

ENTRYPOINT ["/railway_entrypoint.sh"]
