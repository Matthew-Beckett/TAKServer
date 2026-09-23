#!/usr/bin/env bash
# Waits for PostgreSQL, then initializes/upgrades the TAK Server schema via
# SchemaManager.jar. Intended for init containers, Helm hook Jobs, or a
# one-shot `docker run ... dbsetup`.
set -euo pipefail

: "${POSTGRES_HOST:?POSTGRES_HOST is required}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
: "${POSTGRES_DB:?POSTGRES_DB is required}"
: "${POSTGRES_USER:?POSTGRES_USER is required}"
: "${POSTGRES_PASSWORD:?POSTGRES_PASSWORD is required}"

DB_URL="jdbc:postgresql://${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}"

echo "[db-setup] waiting for postgres at ${POSTGRES_HOST}:${POSTGRES_PORT}..."
until nc -zw3 "$POSTGRES_HOST" "$POSTGRES_PORT"; do sleep 2; done

cd "${TAK_HOME:-/opt/tak}"

# Creates the role/database when missing. Non-fatal if it already exists.
java -jar SchemaManager.jar -url "$DB_URL" -user "$POSTGRES_USER" -password "$POSTGRES_PASSWORD" SetupGenericDatabase \
  || echo "[db-setup] SetupGenericDatabase returned non-zero - continuing to upgrade"

java -jar SchemaManager.jar -url "$DB_URL" -user "$POSTGRES_USER" -password "$POSTGRES_PASSWORD" upgrade
echo "[db-setup] schema upgrade complete"

# Terminate an Istio sidecar if one is injected so Jobs can complete.
if curl -sL --fail --max-time 3 http://localhost:15021/healthz/ready -o /dev/null 2>/dev/null; then
  curl -fsI -X POST --max-time 3 http://localhost:15020/quitquitquit || true
fi
