# takserver

Single-node TAK Server. One pod runs the `all` container role — config,
messaging and api services as embedded JVMs with an embedded Ignite node —
backed by a bundled PostGIS database. Certificates are generated at install
time. Everything is exposed over a ClusterIP service.

Use this chart for development, evaluation and small standalone deployments.
For an individually scalable microservices deployment see
[`charts/takserver-cluster`](../takserver-cluster/README.md).

## Prerequisites

- Kubernetes 1.25+
- Helm 3.x

No `helm dependency build` step is required - the chart is self-contained.
Persistence is disabled by default (emptyDir everywhere), so no CSI driver or
StorageClass is needed; enable `postgresql.persistence.enabled` and/or
`logs.persistence.enabled` explicitly for durable deployments.

## Install

```sh
helm install tak charts/takserver -n tak --create-namespace
```

The pre-install job generates a CA, server and client certificates into the
`<release>-takserver-certs` Secret, then the bundled PostGIS database and the
TAK Server pod come up. First start runs schema migrations and can take
several minutes.

```sh
kubectl -n tak rollout status deploy/tak-takserver --timeout=10m
```

## Access

The service `<release>-takserver` (ClusterIP) exposes:

| Port | Purpose |
|---|---|
| 8089 | CoT streaming input (mutual TLS) |
| 8443 | WebTAK / admin UI / REST API (client certificate) |
| 8444 | Federation HTTPS (federation truststore) |
| 8446 | Certificate enrollment (no client auth) |
| 9000 / 9001 | Federation v1 / v2 (when `federation.enabled=true`) |

Port-forward to reach it from a workstation:

```sh
kubectl -n tak port-forward svc/tak-takserver 8443:8443 8089:8089
```

### Client certificates

The generated certs Secret holds the CA, the server keystore and ready-made
`admin` and `user` client certificates:

```sh
kubectl -n tak get secret tak-takserver-certs -o jsonpath='{.data.admin\.p12}' | base64 -d > admin.p12
kubectl -n tak get secret tak-takserver-certs -o jsonpath='{.data.user\.p12}'  | base64 -d > user.p12
kubectl -n tak get secret tak-takserver-certs -o jsonpath='{.data.ca\.pem}'    | base64 -d > ca.pem
```

Default keystore/truststore password is `atakatak`
(`certs.keystorePassword`). Import `admin.p12` into a browser to reach the
admin UI at `https://localhost:8443`, or build an ATAK data package with
`ca.pem` + `user.p12`.

## Bring your own

| What | How |
|---|---|
| Certificates | `certs.existingSecret=<name>` - Secret keys are file names mounted at `/opt/tak/certs/files` (must include `takserver.jks`, `truststore-root.jks`, `fed-truststore.jks`) |
| CoreConfig.xml | `coreConfig.existingSecret=<name>` - must contain a `CoreConfig.xml` key |
| Database | `postgresql.enabled=false` + `database.host=<host>` + `database.existingSecret` (key `password`) or `global.postgresql.auth.password` |
| Registry mirror | `global.image.registry=registry.example.com` repoints every image |

## Upgrades and certificate rotation

The cert Secret is created once and never overwritten - upgrades reuse the
existing CA so client certs keep working. It is also intentionally not owned
by the release: `helm uninstall` leaves it (and the PVCs) behind. To fully
reset a deployment:

```sh
kubectl -n tak delete secret tak-takserver-certs
kubectl -n tak delete pvc -l app.kubernetes.io/instance=tak
```

## Security notes

This chart optimizes for fire-and-forget usability, not hardening:

- The generated Secret includes the CA private key (`ca-do-not-share.key`) so
  anyone who can read the Secret can mint client certs. Use
  `certs.existingSecret` with a curated key set for anything real.
- `global.postgresql.auth.password` defaults to a well-known dev value.
- The certgen hook job needs `secrets get/create` in the release namespace
  (created only when `certs.existingSecret` is unset and `rbac.create=true`).

## Notable values

| Key | Default | Description |
|---|---|---|
| `image.tag` | appVersion | takserver image tag |
| `replicaCount` | `1` | embedded Ignite - do not scale |
| `service.type` | `ClusterIP` | set `LoadBalancer`/`NodePort` to expose externally |
| `federation.enabled` | `true` | federation config + ports 9000/9001 |
| `plugins.enabled` | `false` | also run takserver-pm.jar in the pod |
| `postgresql.enabled` | `true` | bundled PostGIS database |
| `postgresql.persistence.enabled` | `false` | PVC for database data instead of emptyDir |
| `logs.persistence.enabled` | `false` | PVC for `/opt/tak/logs` instead of emptyDir |
| `heap.{config,messaging,api}MaxHeapMb` | `1024/2048/1024` | per-service `-Xmx` |

See `values.yaml` for the full, commented list.
