#!/bin/sh
# Ready once the API service is listening and the database is reachable.
set -e
grep -q 'Tomcat started on port' /opt/tak/logs/takserver-api.log 2>/dev/null
nc -zw3 "${POSTGRES_HOST:-127.0.0.1}" "${POSTGRES_PORT:-5432}"
