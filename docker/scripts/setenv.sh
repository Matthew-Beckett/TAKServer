#!/bin/sh
# Shared runtime environment for all TAK Server container roles.
# Sourced by entrypoint.sh before launching any java process.

TAK_HOME="${TAK_HOME:-/opt/tak}"

# JVM flags carried by the upstream cluster setenv.sh.
# loader.path lets the Spring Boot launcher pick up extra jars dropped in
# ${TAK_HOME}/lib. The netty/tmp dirs must be writable by the non-root user.
export JDK_JAVA_OPTIONS="${JDK_JAVA_OPTIONS:-} -Dloader.path=WEB-INF/lib-provided,WEB-INF/lib,WEB-INF/classes,file:lib/ -Dio.netty.tmpdir=${TAK_HOME} -Djava.io.tmpdir=${TAK_HOME} -Dio.netty.native.workdir=${TAK_HOME} -Djava.net.preferIPv4Stack=true -Djava.security.egd=file:/dev/./urandom -DIGNITE_UPDATE_NOTIFIER=false -DIGNITE_QUIET=true -Djdk.tls.client.protocols=TLSv1.2"

# Embedded/client Ignite writes its work directory under IGNITE_HOME.
export IGNITE_HOME="${TAK_HOME}"

# Maximum heap as a percentage of the container memory limit. Individual roles
# can override with an absolute value via <ROLE>_MAX_HEAP_MB (see entrypoint.sh).
export MAX_HEAP_PERCENT="${MAX_HEAP_PERCENT:-90}"
