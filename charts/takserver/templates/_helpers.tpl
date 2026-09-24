{{/*
Expand the name of the chart.
*/}}
{{- define "takserver.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "takserver.fullname" -}}
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
{{- define "takserver.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Common labels
*/}}
{{- define "takserver.labels" -}}
helm.sh/chart: {{ include "takserver.chart" . }}
{{ include "takserver.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
Selector labels
*/}}
{{- define "takserver.selectorLabels" -}}
app.kubernetes.io/name: {{ include "takserver.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Create the name of the service account the takserver pod uses.
*/}}
{{- define "takserver.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "takserver.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/*
Create the name of the service account used by the cert generation job.
*/}}
{{- define "takserver.certgenServiceAccountName" -}}
{{- if .Values.rbac.create -}}
{{- printf "%s-certgen" (include "takserver.fullname" .) -}}
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
{{- define "takserver.image" -}}
{{- $registry := .global.image.registry | default .image.registry | default "docker.io" -}}
{{- $tag := .image.tag | default .appVersion -}}
{{- printf "%s/%s:%s" $registry .image.repository $tag -}}
{{- end -}}

{{/*
Name of the Secret holding the generated (or user-supplied) certificates.
*/}}
{{- define "takserver.certsSecretName" -}}
{{- if .Values.certs.existingSecret -}}
{{- .Values.certs.existingSecret -}}
{{- else -}}
{{- default (printf "%s-certs" (include "takserver.fullname" .)) .Values.certs.secretName -}}
{{- end -}}
{{- end -}}

{{/*
Name of the Secret holding CoreConfig.xml.
*/}}
{{- define "takserver.coreConfigSecretName" -}}
{{- default (printf "%s-coreconfig" (include "takserver.fullname" .)) .Values.coreConfig.existingSecret -}}
{{- end -}}

{{/*
Database hostname: bundled postgres service or the configured external host.
*/}}
{{- define "takserver.dbHost" -}}
{{- if .Values.postgresql.enabled -}}
{{- printf "%s-db" (include "takserver.fullname" .) -}}
{{- else -}}
{{- required "database.host is required when postgresql.enabled=false" .Values.database.host -}}
{{- end -}}
{{- end -}}

{{/*
Database port.
*/}}
{{- define "takserver.dbPort" -}}
{{- if .Values.postgresql.enabled -}}
{{- .Values.postgresql.service.port -}}
{{- else -}}
{{- .Values.database.port | default 5432 -}}
{{- end -}}
{{- end -}}

{{/*
Name of the Secret holding the database password:
database.existingSecret > global.postgresql.auth.existingSecret >
chart-managed secret.
*/}}
{{- define "takserver.dbSecretName" -}}
{{- if .Values.database.existingSecret -}}
{{- .Values.database.existingSecret -}}
{{- else if .Values.global.postgresql.auth.existingSecret -}}
{{- .Values.global.postgresql.auth.existingSecret -}}
{{- else -}}
{{- printf "%s-db" (include "takserver.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
Pod imagePullSecrets combining global and per-image lists.
Expects a dict {context: $, image: <optional image values block>}.
*/}}
{{- define "takserver.imagePullSecrets" -}}
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
