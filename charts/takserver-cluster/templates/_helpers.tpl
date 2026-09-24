{{/*
Expand the name of the chart.
*/}}
{{- define "takserver-cluster.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "takserver-cluster.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "takserver-cluster.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Common labels
*/}}
{{- define "takserver-cluster.labels" -}}
helm.sh/chart: {{ include "takserver-cluster.chart" . }}
{{ include "takserver-cluster.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
Selector labels
*/}}
{{- define "takserver-cluster.selectorLabels" -}}
app.kubernetes.io/name: {{ include "takserver-cluster.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Labels for a component. Pass a dict {context: $, component: "messaging"}.
*/}}
{{- define "takserver-cluster.componentLabels" -}}
helm.sh/chart: {{ include "takserver-cluster.chart" .context }}
{{ include "takserver-cluster.selectorLabels" .context }}
app.kubernetes.io/version: {{ .context.Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .context.Release.Service }}
app.kubernetes.io/component: {{ .component }}
{{- end -}}

{{/*
Selector labels for a component.
*/}}
{{- define "takserver-cluster.componentSelectorLabels" -}}
{{ include "takserver-cluster.selectorLabels" .context }}
app.kubernetes.io/component: {{ .component }}
{{- end -}}

{{/*
Name of the shared service account used by TAK Server pods and Ignite nodes
for Kubernetes discovery (endpoints/pods read).
*/}}
{{- define "takserver-cluster.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default "takserver-ignite" .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/*
Name of the service account used by the cert generation job.
*/}}
{{- define "takserver-cluster.certgenServiceAccountName" -}}
{{- if .Values.rbac.create -}}
{{- printf "%s-certgen" (include "takserver-cluster.fullname" .) -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/*
Return a fully qualified image reference for a values image block
(registry, repository, tag, pullPolicy). .Values.global.image.registry takes
precedence so a single value can repoint every image for air-gapped or
mirrored registries; an empty image tag falls back to the chart appVersion.
*/}}
{{- define "takserver-cluster.image" -}}
{{- $registry := .global.image.registry | default .image.registry | default "docker.io" -}}
{{- $tag := .image.tag | default .appVersion -}}
{{- printf "%s/%s:%s" $registry .image.repository $tag -}}
{{- end -}}

{{/*
Name of the Secret holding the generated (or user-supplied) certificates.
*/}}
{{- define "takserver-cluster.certsSecretName" -}}
{{- if .Values.certs.existingSecret -}}
{{- .Values.certs.existingSecret -}}
{{- else -}}
{{- default (printf "%s-certs" (include "takserver-cluster.fullname" .)) .Values.certs.secretName -}}
{{- end -}}
{{- end -}}

{{/*
Name of the Secret holding CoreConfig.xml.
*/}}
{{- define "takserver-cluster.coreConfigSecretName" -}}
{{- default (printf "%s-coreconfig" (include "takserver-cluster.fullname" .)) .Values.coreConfig.existingSecret -}}
{{- end -}}

{{/*
Name of the ConfigMap holding TAKIgniteConfig.xml.
*/}}
{{- define "takserver-cluster.igniteConfigMapName" -}}
{{- default (printf "%s-igniteconfig" (include "takserver-cluster.fullname" .)) .Values.igniteConfig.existingConfigMap -}}
{{- end -}}

{{/*
Name of the bundled postgresql subchart's primary service.
*/}}
{{- define "takserver-cluster.postgresServiceName" -}}
{{- printf "%s-postgresql" .Release.Name -}}
{{- end -}}

{{/*
Database hostname: bundled postgresql service or the configured external host.
*/}}
{{- define "takserver-cluster.dbHost" -}}
{{- if .Values.postgresql.enabled -}}
{{- include "takserver-cluster.postgresServiceName" . -}}
{{- else -}}
{{- required "database.host is required when postgresql.enabled=false" .Values.database.host -}}
{{- end -}}
{{- end -}}

{{/*
Database port.
*/}}
{{- define "takserver-cluster.dbPort" -}}
{{- .Values.database.port | default 5432 -}}
{{- end -}}

{{/*
Name of the Secret holding database credentials:
database.existingSecret > global.postgresql.auth.existingSecret >
bundled subchart secret > chart-managed secret (external DB).
*/}}
{{- define "takserver-cluster.dbSecretName" -}}
{{- if .Values.database.existingSecret -}}
{{- .Values.database.existingSecret -}}
{{- else if .Values.global.postgresql.auth.existingSecret -}}
{{- .Values.global.postgresql.auth.existingSecret -}}
{{- else if .Values.postgresql.enabled -}}
{{- include "takserver-cluster.postgresServiceName" . -}}
{{- else -}}
{{- printf "%s-db" (include "takserver-cluster.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
NATS cluster URL for CoreConfig <cluster natsURL=...>.
*/}}
{{- define "takserver-cluster.natsUrl" -}}
{{- if .Values.cluster.natsUrl -}}
{{- .Values.cluster.natsUrl -}}
{{- else -}}
{{- printf "nats://%s-nats:4222" .Release.Name -}}
{{- end -}}
{{- end -}}

{{/*
Pod imagePullSecrets combining global and per-image lists.
Expects a dict {context: $, image: <image values block>}.
*/}}
{{- define "takserver-cluster.imagePullSecrets" -}}
{{- $secrets := .context.Values.global.imagePullSecrets | default list -}}
{{- $img := .image | default dict -}}
{{- if $img.pullSecrets -}}
{{- $secrets = concat $secrets $img.pullSecrets -}}
{{- end -}}
{{- if $secrets }}
imagePullSecrets:
{{- range $secrets }}
  - name: {{ .name | default . }}
{{- end }}
{{- end }}
{{- end -}}

{{/*
Shared volume mounts for TAK Server containers (core config, ignite config,
certs, logs). Expects the component dict to carry .context.
*/}}
{{- define "takserver-cluster.volumeMounts" -}}
- name: core-config
  mountPath: /opt/tak/CoreConfig.xml
  subPath: CoreConfig.xml
- name: tak-ignite-config
  mountPath: /opt/tak/TAKIgniteConfig.xml
  subPath: TAKIgniteConfig.xml
- name: certs
  mountPath: /opt/tak/certs/files
  readOnly: true
- name: logs
  mountPath: /opt/tak/logs
{{- end -}}

{{/*
Shared volumes for TAK Server pods.
*/}}
{{- define "takserver-cluster.volumes" -}}
- name: core-config
  secret:
    secretName: {{ include "takserver-cluster.coreConfigSecretName" . }}
- name: tak-ignite-config
  configMap:
    name: {{ include "takserver-cluster.igniteConfigMapName" . }}
- name: certs
  secret:
    secretName: {{ include "takserver-cluster.certsSecretName" . }}
- name: logs
  emptyDir: {}
{{- end -}}

{{/*
Common POSTGRES_* environment for TAK Server containers.
*/}}
{{- define "takserver-cluster.dbEnv" -}}
- name: POSTGRES_HOST
  value: {{ include "takserver-cluster.dbHost" . | quote }}
- name: POSTGRES_PORT
  value: {{ include "takserver-cluster.dbPort" . | quote }}
- name: POSTGRES_DB
  value: {{ .Values.global.postgresql.auth.database | quote }}
- name: POSTGRES_USER
  value: {{ .Values.global.postgresql.auth.username | quote }}
- name: POSTGRES_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "takserver-cluster.dbSecretName" . }}
      key: {{ .Values.database.existingSecretPasswordKey }}
{{- end -}}
