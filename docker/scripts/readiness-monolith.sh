#!/bin/sh
# Ready once the all-in-one server's messaging process is up and DB reachable.
set -e
grep -q 'com.bbn.marti.nio.server.NioServer - Server started' /opt/tak/logs/takserver-messaging.log 2>/dev/null
nc -zw3 "${POSTGRES_HOST:-127.0.0.1}" "${POSTGRES_PORT:-5432}"
