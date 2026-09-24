# takserver-cluster

Clustered TAK Server as individually scalable microservices — the "HA"
counterpart to [`charts/takserver`](../takserver/README.md)

| Component | Kind | Default replicas | Role |
|---|---|---|---|
| config | Deployment | 1 | centralized configuration (must start first) |
| messaging | Deployment | 2 | CoT TLS input (8089), federation (9000/9001) |
| api | Deployment | 2 | web UI / REST (8443), fed HTTPS (8444), enrollment (8446) |
| plugins | Deployment | 0 (`plugins.enabled`) | takserver-pm.jar, `k8cluster` profile |
| ignite | StatefulSet (subchart) | 2 | cluster state / service mesh between nodes |
| nats | StatefulSet (subchart) | 3 | cluster message bus (`ClusterManager`) |
| postgresql | StatefulSet (subchart) | 1 | PostGIS database |

## Prerequisites

- Kubernetes 1.25+, Helm 3.x
- No StorageClass required by default - all persistence (postgresql data,
  ignite, nats jetstream fileStore) is disabled in favor of emptyDir/memory.
  Enable `postgresql.primary.persistence.enabled` and/or
  `ignite.persistence.enabled` explicitly on clusters with a CSI driver.
- Vendored dependencies are committed under `charts/` - `helm install` works
  directly. After editing `third-party/ignite` or bumping versions in
  `Chart.yaml`, re-vendor with:
  ```sh
  helm dependency update charts/takserver-cluster
  ```

## Install

```sh
helm install tak charts/takserver-cluster -n takserver --create-namespace
```

Install order is handled by Helm hooks:

1. `certgen` (pre-install): generates CA/server/client certs into the
   `<release>-takserver-cluster-certs` Secret unless it already exists.
2. Subcharts + Deployments: ignite StatefulSet, nats, postgresql, then the
   TAK pods (their init containers wait for Postgres and Ignite discovery).
3. `dbsetup` (post-install/post-upgrade): creates the `cot` database if
   missing, then runs SchemaManager `SetupGenericDatabase` + `upgrade`.

```sh
kubectl -n takserver rollout status deploy/tak-takserver-cluster-messaging --timeout=10m
kubectl -n takserver rollout status deploy/tak-takserver-cluster-api --timeout=10m
```

## Access

ClusterIP services (per-service `service.type` is overridable):

| Service | Ports |
|---|---|
| `<release>-takserver-cluster-messaging` | 8089 CoT mTLS, 9000/9001 federation |
| `<release>-takserver-cluster-api` | 8443 web/admin, 8444 fed HTTPS, 8446 enrollment |

```sh
kubectl -n takserver port-forward svc/tak-takserver-cluster-api 8443:8443
kubectl -n takserver port-forward svc/tak-takserver-cluster-messaging 8089:8089
```

Client certs (`admin.p12`, `user.p12`, `ca.pem`) live in the
`<release>-takserver-cluster-certs` Secret — see the single-node chart's
README for extraction commands.

## Scaling

Each microservice scales independently:

```sh
helm upgrade tak charts/takserver-cluster -n takserver \
  --set messaging.replicas=8 --set api.replicas=4 --set ignite.replicaCount=3
```

Cluster state is shared through Ignite, so all messaging pods see all
connected clients. Upstream cluster caveats apply (see
`src/takserver-cluster/README.md`): the admin "client dashboard"/metrics only
show the messaging pod a connection lands on, and mission contacts can be
inconsistent.

## Hardcoded upstream values

TAK Server's Kubernetes Ignite discovery has two hardcoded values
(`IgniteConfigurationHolder`, `TakclIgniteHelper`):

- The Ignite headless Service **must** be named `takserver-ignite`
  (the chart pins `ignite.fullnameOverride` — do not change it).
- `admin.register=true` additionally requires `.Release.Namespace` to be
  `takserver` — `TAKCL_K8S_MODE` discovery hardcodes that namespace. The
  chart fails to render otherwise.

## Admin certificate registration

With `admin.register=false` (default) the generated `admin.pem`/`admin.p12`
client certificate is **not** auto-granted `ROLE_ADMIN`. Register it once the
messaging pods are ready (works in any namespace when executed in-pod):

```sh
kubectl -n takserver exec deploy/tak-takserver-cluster-messaging -- \
  env TAKCL_K8S_MODE=true java -jar UserManager.jar certmod -A certs/files/admin.pem
```

(`TAKCL_K8S_MODE=true` still expects namespace `takserver`; for other
namespaces register the cert via the enrollment service on 8446 or manage
`UserAuthenticationFile.xml` yourself.)

## Bring your own dependencies

Every bundled dependency can be disabled and replaced:

```yaml
postgresql:
  enabled: false
database:
  host: db.example.com
  port: 5432
  existingSecret: my-db-secret        # holds the user password
  existingSecretPasswordKey: password
nats:
  enabled: false
cluster:
  natsUrl: nats://nats.example.com:4222
ignite:
  enabled: false   # you must provide a headless Service named
                   # "takserver-ignite" in the release namespace
certs:
  existingSecret: my-tak-certs
coreConfig:
  existingSecret: my-coreconfig       # contains key CoreConfig.xml
igniteConfig:
  existingConfigMap: my-igniteconfig  # contains key TAKIgniteConfig.xml
```

Note that disabling the bundled postgres also skips the `ensure-database`
init step — create the database and user yourself (the `dbsetup` job still
runs schema migrations unless `dbSetup.enabled=false`).

## Registry override (air-gapped)

```sh
helm upgrade tak charts/takserver-cluster -n takserver \
  --set global.image.registry=registry.example.com \
  --set global.imageRegistry=registry.example.com
```

`global.image.registry` repoints the takserver, takserver-ca, takserver-ignite
and nats images; `global.imageRegistry` is the bitnami-native knob the
postgresql subchart honors (postgis image).

## Notable values

| Key | Default | Description |
|---|---|---|
| `config/messaging/api.replicas` | `1/2/2` | per-service replica counts |
| `*.maxHeapMb` | `1024/2048/2048` | per-service `-Xmx` (plugins: `512`) |
| `plugins.enabled` | `false` | plugin manager deployment |
| `federation.enabled` | `true` | federation config + ports |
| `admin.register` | `false` | auto `certmod -A` the admin cert (needs ns `takserver`) |
| `dbSetup.enabled` | `true` | schema init/upgrade hook job |
| `global.postgresql.auth.*` | `martiuser`/`atakatak`/`cot` | single source of DB credentials |
| `postgresql.enabled` / `nats.enabled` / `ignite.enabled` | `true` | bundled dependency toggles |

See `values.yaml` for the full, commented list.
