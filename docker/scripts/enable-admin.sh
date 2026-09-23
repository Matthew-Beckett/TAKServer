#!/usr/bin/env bash
# Registers the admin client certificate with the server once it is up.
# Run in the background by entrypoint.sh for the messaging and all roles.
# $1 = log file to watch for the "Server started" marker.

set -u

ADMIN_CERT="${ADMIN_CERT:-certs/files/admin.pem}"
LOG_FILE="${1:-logs/takserver-messaging.log}"

# TAKCL (UserManager/certmod) resolves config via these env vars.
export TAKCL_CORECONFIG_PATH="${TAK_HOME:-/opt/tak}/CoreConfig.xml"
export TAKCL_TAKIGNITECONFIG_PATH="${TAK_HOME:-/opt/tak}/TAKIgniteConfig.xml"

if [ ! -f "$ADMIN_CERT" ]; then
  echo "[enable-admin] no admin certificate at $ADMIN_CERT - skipping admin registration"
  exit 0
fi

echo "[enable-admin] waiting for server startup ($LOG_FILE)..."
while ! grep -q 'com.bbn.marti.nio.server.NioServer - Server started' "$LOG_FILE" 2>/dev/null; do
  sleep 5
done

echo "[enable-admin] registering $ADMIN_CERT as admin"
until java -jar UserManager.jar certmod -A "$ADMIN_CERT"; do
  echo "[enable-admin] certmod failed - retrying in 5s"
  sleep 5
done
echo "[enable-admin] admin certificate registered"
