# Redpanda (Kafka API) for Hive usage reporting, single node.
# Starts as root to own the Railway volume, then drops to the `redpanda` user.
FROM redpandadata/redpanda:v23.3.21

USER root
COPY entrypoint.sh /railway_entrypoint.sh
RUN chmod +x /railway_entrypoint.sh

EXPOSE 29092 9644

ENTRYPOINT ["/railway_entrypoint.sh"]
