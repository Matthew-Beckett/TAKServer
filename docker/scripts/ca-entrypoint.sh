#!/usr/bin/env bash
# Certificate toolkit entrypoint.
#   docker run ... takserver-ca                        -> generateClusterCerts.sh
#   docker run ... takserver-ca ./makeCert.sh client u -> run the given command
#
# Certificates are written to /opt/tak/certs/files - mount a volume there to
# collect them.
set -e
cd /opt/tak/certs

if [ $# -eq 0 ]; then
  : "${CA_NAME:?set -e CA_NAME=<name for your CA>}"
  : "${STATE:?set -e STATE=...}"
  : "${CITY:?set -e CITY=...}"
  : "${ORGANIZATIONAL_UNIT:?set -e ORGANIZATIONAL_UNIT=...}"
  exec ./generateClusterCerts.sh
fi
exec "$@"
