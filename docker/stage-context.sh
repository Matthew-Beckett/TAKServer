#!/usr/bin/env bash
# Stages docker/context/ with everything the image builds need.
#
# Requires the Gradle build to have run first:
#   cd src && ./gradlew :takserver-core:bootWar :takserver-plugin-manager:bootJar \
#     :takserver-usermanager:shadowJar :takserver-schemamanager:shadowJar \
#     :takserver-common:igniteExtensions
#
# NOTE: CoreConfig.xml and TAKIgniteConfig.xml are deliberately NOT staged -
# they are environment-specific and must be mounted at runtime.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/src"
CTX="$ROOT/docker/context"

die() { echo "stage-context: ERROR: $*" >&2; exit 1; }

# pick <glob> <target-name> - copies the newest matching build artifact.
pick() {
  local pattern="$1" target="$2" f
  # shellcheck disable=SC2086,SC2012
  f=$(ls -1t $pattern 2>/dev/null | head -n1 || true)
  [ -n "$f" ] || die "no match for $pattern - run the Gradle build first"
  cp "$f" "$CTX/$target"
  echo "  $(basename "$f") -> context/$target"
}

rm -rf "$CTX"
mkdir -p "$CTX"

echo "staging build artifacts into docker/context/"
pick "$SRC/takserver-core/build/libs/takserver-core-*.war"                    takserver.war
pick "$SRC/takserver-plugin-manager/build/libs/takserver-plugin-manager-*.jar" takserver-pm.jar
pick "$SRC/takserver-usermanager/build/libs/UserManager-*-all.jar"          UserManager.jar
pick "$SRC/takserver-schemamanager/build/libs/schemamanager-*-uber.jar"     SchemaManager.jar
pick "$SRC/takserver-common/build/libs/ignite-extensions-*.jar"             ignite-extensions.jar

# Static, non-secret inputs staged verbatim from the source tree.
cp "$SRC/takserver-core/example/UserAuthenticationFile.cluster.xml" "$CTX/UserAuthenticationFile.xml"
cp "$SRC/takserver-core/example/logging-restrictsize.xml"           "$CTX/logging-restrictsize.xml"
cp -R "$SRC/takserver-core/scripts/certs"                           "$CTX/certs"
cp "$SRC/takserver-cluster/docker-files/scripts/takserver-ignite/ignite.sh" "$CTX/ignite.sh"
chmod +x "$CTX/ignite.sh" "$CTX/certs/"*.sh

# Guard rail: no environment-specific config may leak into the build context.
if ls "$CTX"/CoreConfig*.xml "$CTX"/TAKIgniteConfig*.xml 1>/dev/null 2>&1; then
  die "CoreConfig/TAKIgniteConfig must not be staged - they are runtime mounts only"
fi

echo "context contents:"
ls -la "$CTX"
