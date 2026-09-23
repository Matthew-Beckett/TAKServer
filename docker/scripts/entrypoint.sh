#!/usr/bin/env bash
# TAK Server container entrypoint. The first argument selects the role:
#
#   config       - config service only (Spring profile "config")
#   messaging    - CoT messaging service only (Spring profile "messaging")
#   api          - API/WebTAK service only (Spring profile "api")
#   plugins      - plugin manager (takserver-pm.jar, profile "k8cluster")
#   dbsetup      - run SchemaManager against PostgreSQL, then exit
#   usermanager  - run UserManager.jar with the remaining arguments
#   all          - all-in-one standalone: config+messaging+api JVMs in one container
#   <other>      - treated as a command to exec (e.g. "bash")
#
# No CoreConfig.xml, TAKIgniteConfig.xml or certificates are baked into this
# image - mount them at runtime (see docker/README.md).

set -euo pipefail

TAK_HOME="${TAK_HOME:-/opt/tak}"
cd "$TAK_HOME"
# shellcheck source=/dev/null
. "$TAK_HOME/scripts/setenv.sh"

ROLE="${1:-all}"
if [ $# -gt 0 ]; then shift; fi

log()  { echo "[takserver-entrypoint] $*"; }
die()  { echo "[takserver-entrypoint] ERROR: $*" >&2; exit 1; }

require_runtime_files() {
  [ -f CoreConfig.xml ] || die "CoreConfig.xml not found in $TAK_HOME.
    Provide it via a bind mount (-v /path/CoreConfig.xml:/opt/tak/CoreConfig.xml:ro)
    or a Kubernetes ConfigMap/Secret volume. See docker/README.md."
  [ -f certs/files/takserver.jks ] || die "No keystore at $TAK_HOME/certs/files/takserver.jks.
    Mount your certificate directory at /opt/tak/certs (the takserver-ca image
    can generate a development set; see docker/README.md)."
}

require_cluster_config() {
  [ -f TAKIgniteConfig.xml ] || die "TAKIgniteConfig.xml not found in $TAK_HOME.
    Required for the split-process roles. Mount it like CoreConfig.xml, or run
    the 'all' role for a single-container standalone server."
}

# Returns the JVM heap option for a role: -Xmx<N>m if <VAR> is set,
# otherwise -XX:MaxRAMPercentage=<MAX_HEAP_PERCENT>.
jvm_heap_opt() {
  local var_name="$1"
  if [ -n "${!var_name:-}" ]; then
    echo "-Xmx${!var_name}m"
  else
    echo "-XX:MaxRAMPercentage=${MAX_HEAP_PERCENT}"
  fi
}

spring_profiles() {
  local role="$1"
  echo "${SPRING_PROFILES_ACTIVE:-${role},consolelog${TAK_EXTRA_PROFILES:+,${TAK_EXTRA_PROFILES}}}"
}

JVM_COMMON="-server -XX:+AlwaysPreTouch -XX:+UseG1GC -XX:+ScavengeBeforeFullGC -XX:+DisableExplicitGC"

run_war() {
  # $1 = role profile, $2 = heap env var name, $3 = extra -D flags (may be
  # empty), remaining args are passed to the JVM as application arguments.
  local role="$1" heapvar="$2" extra="${3:-}"
  shift 3 || true
  # shellcheck disable=SC2086
  exec java $JVM_COMMON "$(jvm_heap_opt "$heapvar")" $extra \
    "-Dspring.profiles.active=$(spring_profiles "$role")" -jar takserver.war "$@"
}

case "$ROLE" in

  config)
    require_runtime_files
    require_cluster_config
    run_war config CONFIG_MAX_HEAP_MB "-Dkeystore.pkcs12.legacy" "$@"
    ;;

  messaging)
    require_runtime_files
    require_cluster_config
    "$TAK_HOME/scripts/enable-admin.sh" logs/takserver-messaging.log &
    run_war messaging MESSAGING_MAX_HEAP_MB "" "$@"
    ;;

  api)
    require_runtime_files
    require_cluster_config
    run_war api API_MAX_HEAP_MB "-Dkeystore.pkcs12.legacy" "$@"
    ;;

  plugins)
    require_runtime_files
    require_cluster_config
    exec java -Xms128m "-Xmx${PLUGIN_MANAGER_MAX_HEAP_MB:-512}m" \
      "-Dspring.profiles.active=${SPRING_PROFILES_ACTIVE:-k8cluster}" \
      -jar takserver-pm.jar "$@"
    ;;

  all)
    # All-in-one standalone container using the same topology as the upstream
    # 'full' image: the config, messaging and api services as separate JVMs in
    # one container. The messaging JVM hosts the embedded Ignite server that the
    # other services join over localhost discovery (no external Ignite needed).
    require_runtime_files
    if [ -n "${POSTGRES_HOST:-}" ]; then
      "$TAK_HOME/scripts/db-setup.sh"
    else
      log "POSTGRES_HOST not set - skipping DB schema init. Set POSTGRES_* envs or run the 'dbsetup' role first."
    fi
    if [ ! -f TAKIgniteConfig.xml ]; then
      # Standalone uses the embedded Ignite defaults; the admin tooling still
      # needs this file to exist, so create the upstream empty default.
      log "TAKIgniteConfig.xml not found - writing empty standalone default (no cluster settings)."
      printf '<?xml version="1.0" encoding="UTF-8"?>\n<TAKIgniteConfiguration xmlns="http://bbn.com/marti/xml/config"/>\n' > TAKIgniteConfig.xml
    fi

    # shellcheck disable=SC2086
    java $JVM_COMMON "$(jvm_heap_opt CONFIG_MAX_HEAP_MB)" -Dkeystore.pkcs12.legacy \
      "-Dspring.profiles.active=$(spring_profiles config)" -jar takserver.war &
    pids=("$!")
    # shellcheck disable=SC2086
    java $JVM_COMMON "$(jvm_heap_opt MESSAGING_MAX_HEAP_MB)" \
      "-Dspring.profiles.active=$(spring_profiles messaging)" -jar takserver.war "$@" &
    pids+=("$!")
    # shellcheck disable=SC2086
    java $JVM_COMMON "$(jvm_heap_opt API_MAX_HEAP_MB)" -Dkeystore.pkcs12.legacy \
      "-Dspring.profiles.active=$(spring_profiles api)" -jar takserver.war &
    pids+=("$!")
    if [ "${TAK_PLUGINS:-false}" = "true" ]; then
      java -Xms128m "-Xmx${PLUGIN_MANAGER_MAX_HEAP_MB:-512}m" -jar takserver-pm.jar &
      pids+=("$!")
    fi
    "$TAK_HOME/scripts/enable-admin.sh" logs/takserver-messaging.log &

    shutdown() { kill "${pids[@]}" 2>/dev/null || true; }
    trap shutdown TERM INT
    # Exit when the first service exits; kill the rest so the container stops.
    wait -n "${pids[@]}"
    shutdown
    exit 1
    ;;

  dbsetup)
    exec "$TAK_HOME/scripts/db-setup.sh" "$@"
    ;;

  usermanager)
    require_runtime_files
    exec java -jar UserManager.jar "$@"
    ;;

  *)
    exec "$@"
    ;;
esac
