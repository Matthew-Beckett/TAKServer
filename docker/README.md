# TAK Server container images

This directory builds a set of minimal, non-root container images for TAK
Server. It replaces the `src/takserver-cluster/docker-files` images, which
depend on an inaccessible internal registry and bake environment-specific
configuration into image layers.

## Images

| Image | Dockerfile | Purpose |
|---|---|---|
| `takserver` | `Dockerfile.takserver` | All TAK Server roles (`config`, `messaging`, `api`, `plugins`, `dbsetup`, `usermanager`, `all`) |
| `takserver-ignite` | `Dockerfile.takserver-ignite` | Apache Ignite 2.17.0 node with `ignite-extensions.jar` and the Kubernetes discovery module baked in |
| `takserver-ca` | `Dockerfile.takserver-ca` | Certificate toolkit; generates CA/server/client certs into `/opt/tak/certs/files` |

All images run as uid `1001`, group `0` (OpenShift-compatible non-root), and
are based on `eclipse-temurin:17-jre-noble` (Java 17 JRE, minimal).

## Configuration is mounted, not baked in

`CoreConfig.xml` is **never** copied into an image. Neither are
`TAKIgniteConfig.xml` or certificates. Supply them at runtime:

| Path inside container | How to supply | Contents |
|---|---|---|
| `/opt/tak/CoreConfig.xml` | bind mount / ConfigMap or Secret | Server config. Examples: `src/takserver-core/example/CoreConfig.example.docker.xml` (standalone), `CoreConfig.example.cluster.xml` (clustered) |
| `/opt/tak/TAKIgniteConfig.xml` | bind mount / ConfigMap | Ignite client/cluster settings. Required for the split-process roles; optional for `all` (embedded Ignite) |
| `/opt/tak/certs/files/` | bind mount / Secret | `takserver.jks`, `truststore-root.jks`, `fed-truststore.jks`, `admin.pem`, ... produced by `takserver-ca` (mount the generation output dir here) |
| `/opt/tak/logs/` | volume | Log output (file logging plus console when the `consolelog` profile is active) |

Because the DB connection string lives inside the mounted `CoreConfig.xml`,
no credential substitution happens at image build time.

## Roles (`docker run <image> <role>`)

- `all` (default) — all-in-one standalone: runs the `config`, `messaging`
  and `api` services in one container (same topology as the upstream `full`
  image). Messaging hosts an embedded Ignite server, so no external Ignite is
  needed. If `POSTGRES_HOST` is set, schema setup/migration runs first.
- `config` / `messaging` / `api` — individual cluster services.
- `plugins` — plugin manager (`takserver-pm.jar`, `k8cluster` profile).
- `dbsetup` — waits for Postgres, runs `SchemaManager.jar` migrations, exits.
  Requires `POSTGRES_HOST`, `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`
  (`POSTGRES_PORT` defaults to 5432).
- `usermanager` — runs `UserManager.jar` with your args (e.g. `certmod`,
  `usermod`). `CoreConfig.xml` and certs must be mounted.
- Anything else is exec'd verbatim (e.g. `bash` for debugging).

### Environment variables

| Variable | Default | Purpose |
|---|---|---|
| `MAX_HEAP_PERCENT` | `90` | Max heap as % of container memory limit |
| `CONFIG_MAX_HEAP_MB`, `MESSAGING_MAX_HEAP_MB`, `API_MAX_HEAP_MB` | — | Absolute `-Xmx` in MB per role (overrides `MAX_HEAP_PERCENT`) |
| `PLUGIN_MANAGER_MAX_HEAP_MB` | `512` | Plugin manager heap |
| `SPRING_PROFILES_ACTIVE` | `<role>,consolelog` | Overrides the computed Spring profile list |
| `TAK_EXTRA_PROFILES` | — | Extra Spring profiles appended to the default |
| `ADMIN_CERT` | `certs/files/admin.pem` | Admin client cert auto-registered by `messaging`/`all` roles |
| `TAK_PLUGINS` | `false` | `all` role only: also launch `takserver-pm.jar` |
| `POSTGRES_*` | — | Used by `dbsetup`, `all`, and the readiness probes |

## Building locally

```sh
cd src
./gradlew :takserver-core:bootWar :takserver-plugin-manager:bootJar \
  :takserver-usermanager:shadowJar :takserver-schemamanager:shadowJar \
  :takserver-common:igniteExtensions
cd ..

docker/stage-context.sh

docker build -f docker/Dockerfile.takserver        -t takserver        docker/
docker build -f docker/Dockerfile.takserver-ignite -t takserver-ignite docker/
docker build -f docker/Dockerfile.takserver-ca     -t takserver-ca     docker/
```

`stage-context.sh` copies the built artifacts into `docker/context/` (which is
git-ignored) and fails if `CoreConfig*.xml`/`TAKIgniteConfig*.xml` would leak
into the build context.

## Generating certificates (development)

```sh
docker run --rm \
  -e CA_NAME=tak -e STATE=XX -e CITY=XX -e ORGANIZATIONAL_UNIT=tak \
  -v "$PWD/certs/files:/opt/tak/certs/files" \
  takserver-ca
```

Issue additional client certs:

```sh
docker run --rm -v "$PWD/certs/files:/opt/tak/certs/files" \
  takserver-ca ./makeCert.sh client someuser
```

## Standalone Docker usage

See `examples/docker-compose.yml` for a complete single-node stack
(PostGIS + TAK Server `all` role).

## Kubernetes usage

Deploy the roles as separate containers, mounting configuration:

```yaml
volumeMounts:
  - name: core-config
    mountPath: /opt/tak/CoreConfig.xml
    subPath: CoreConfig.xml
  - name: tak-ignite-config
    mountPath: /opt/tak/TAKIgniteConfig.xml
    subPath: TAKIgniteConfig.xml
  - name: certs
    mountPath: /opt/tak/certs/files
    readOnly: true
    # note: if your Secret/ConfigMap is read-only, the app only reads these
    # files; logs go to /opt/tak/logs (mount an emptyDir or PVC there)
volumes:
  - name: core-config
    secret:                       # CoreConfig contains DB credentials
      secretName: takserver-core-config
  - name: tak-ignite-config
    configMap:
      name: tak-ignite-config
  - name: certs
    secret:
      secretName: takserver-certs   # keys are the cert filenames
```

container `args: ["messaging"]` (or `config` / `api` / `plugins`). Exec
readiness probes are available:

- `/opt/tak/scripts/readiness-config.sh`
- `/opt/tak/scripts/readiness-messaging.sh`
- `/opt/tak/scripts/readiness-api.sh`
- `/opt/tak/scripts/readiness-monolith.sh` (for the `all` role; checks the
  messaging process and DB reachability)

Database schema setup can run as an init Job with `args: ["dbsetup"]` and the
`POSTGRES_*` env vars from a Secret.

## CI

`.github/workflows/build-images.yml` builds the Java artifacts with Gradle
(JDK 17, cached), stages `docker/context/`, then builds and pushes all three
images to GHCR with BuildKit/GHA layer caching. Tags: the TAK Server version
(from the built war name), `sha-<commit>`, and `latest` on the default branch.
