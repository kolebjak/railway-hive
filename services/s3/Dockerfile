# versitygw: S3-compatible store for schema artifacts and audit logs.
# One volume (Railway allows one per service) holds both the bucket root and
# the posix-backend metadata sidecar.
FROM ghcr.io/versity/versitygw:v1.8.0

COPY entrypoint.sh /railway_entrypoint.sh
RUN chmod +x /railway_entrypoint.sh

ENV PORT=9000
EXPOSE 9000

ENTRYPOINT ["/railway_entrypoint.sh"]
