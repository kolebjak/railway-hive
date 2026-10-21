# Bitnami Redis runs as uid 1001 and cannot write a root-owned Railway volume.
# Started as root its own scripts chown the data dir and drop to the redis user.
FROM bitnamilegacy/redis:7.4.2

USER root

EXPOSE 6379
