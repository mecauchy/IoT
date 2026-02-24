{{/*
=============================================================================
HELM TEMPLATE HELPERS
=============================================================================
These are Go template functions that generate consistent names and labels
across all resources in the chart.

Helm uses Go templates with Sprig functions for advanced templating.
The {{- ... -}} syntax trims whitespace.
=============================================================================
*/}}

{{/*
Expand the name of the chart.
Used as a base for resource names.
*/}}
{{- define "playground.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited.
If release name contains chart name it will be used as a full name.
*/}}
{{- define "playground.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version for the chart label.
*/}}
{{- define "playground.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels applied to all resources.
These labels help with:
- Identifying resources that belong to this chart
- Helm upgrade/rollback tracking
- Monitoring and logging queries
*/}}
{{- define "playground.labels" -}}
helm.sh/chart: {{ include "playground.chart" . }}
{{ include "playground.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels used for Service -> Pod matching.
These must be consistent between Deployment and Service.
*/}}
{{- define "playground.selectorLabels" -}}
app.kubernetes.io/name: {{ include "playground.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app: playground
{{- end }}
