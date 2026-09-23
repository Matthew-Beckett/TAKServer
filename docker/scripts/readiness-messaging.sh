#!/bin/sh
# Ready once the messaging server is up, the database is reachable, and (if an
# admin cert is mounted) the admin user has been registered.
set -e
grep -q 'com.bbn.marti.nio.server.NioServer - Server started' /opt/tak/logs/takserver-messaging.log 2>/dev/null
nc -zw3 "${POSTGRES_HOST:-127.0.0.1}" "${POSTGRES_PORT:-5432}"
if [ -f "${ADMIN_CERT:-/opt/tak/certs/files/admin.pem}" ]; then
  grep -q 'ROLE_ADMIN' /opt/tak/UserAuthenticationFile.xml 2>/dev/null
fi
