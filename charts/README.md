# TAK Server Helm charts

| Chart | Topology | Use when |
|---|---|---|
| [`takserver`](takserver/README.md) | Single pod running the `all` role (config+messaging+api in one container, embedded Ignite) + bundled PostGIS | development, evaluation, small standalone servers |
| [`takserver-cluster`](takserver-cluster/README.md) | Separate scalable Deployments for `config`, `messaging`, `api`, `plugins` + Ignite, NATS and PostgreSQL subcharts | clustered production deployments |
