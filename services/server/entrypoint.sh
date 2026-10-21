#!/bin/sh
# Fills SUPERTOKENS_ACCESS_TOKEN_KEY ("<id>|<rsa pub b64>|<rsa priv b64>") when
# it is not set: reuse the key in the volume, else generate and store it.
# An explicit SUPERTOKENS_ACCESS_TOKEN_KEY always wins (e.g. migrating an instance).
set -eu

KEY_FILE="${HIVE_KEYS_DIR:-/keys}/supertokens-access-token-key"

if [ -z "${SUPERTOKENS_ACCESS_TOKEN_KEY:-}" ]; then
  if [ -s "$KEY_FILE" ]; then
    SUPERTOKENS_ACCESS_TOKEN_KEY="$(cat "$KEY_FILE")"
    echo "INFO: SUPERTOKENS_ACCESS_TOKEN_KEY loaded from $KEY_FILE"
  else
    priv="$(openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 2>/dev/null)"
    pub="$(printf '%s\n' "$priv" | openssl rsa -pubout 2>/dev/null)"
    body() { grep -v -- '-----' | tr -d '\n'; }
    SUPERTOKENS_ACCESS_TOKEN_KEY="$(openssl rand -hex 16)|$(printf '%s\n' "$pub" | body)|$(printf '%s\n' "$priv" | body)"
    if mkdir -p "$(dirname "$KEY_FILE")" 2>/dev/null \
       && (umask 077 && printf '%s' "$SUPERTOKENS_ACCESS_TOKEN_KEY" > "$KEY_FILE") 2>/dev/null; then
      echo "INFO: SUPERTOKENS_ACCESS_TOKEN_KEY generated and stored in $KEY_FILE"
    else
      echo "WARN: no writable volume at $(dirname "$KEY_FILE"); key is ephemeral, every redeploy logs all users out" >&2
    fi
  fi
  export SUPERTOKENS_ACCESS_TOKEN_KEY
fi

exec /entrypoint.sh
