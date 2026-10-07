{{/* Expand the name of the chart. */}}
{{- define "workload.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Create a default fully qualified app name. */}}
{{- define "workload.fullname" -}}
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

{{/* Create chart name and version as used by the chart label. */}}
{{- define "workload.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Common labels. */}}
{{- define "workload.labels" -}}
helm.sh/chart: {{ include "workload.chart" . }}
{{ include "workload.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/* Selector labels. */}}
{{- define "workload.selectorLabels" -}}
app.kubernetes.io/name: {{ include "workload.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/* Create the name of the ServiceAccount to use. */}}
{{- define "workload.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "workload.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/* Allow the release namespace to be overridden. */}}
{{- define "workload.namespace" -}}
{{- default .Release.Namespace .Values.namespaceOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Render only explicitly configured probe objects. */}}
{{- define "workload.probes" -}}
{{- if kindIs "map" .Values.startupProbe }}
startupProbe:
  {{- toYaml .Values.startupProbe | nindent 2 }}
{{- end }}
{{- if kindIs "map" .Values.readinessProbe }}
readinessProbe:
  {{- toYaml .Values.readinessProbe | nindent 2 }}
{{- end }}
{{- if kindIs "map" .Values.livenessProbe }}
livenessProbe:
  {{- toYaml .Values.livenessProbe | nindent 2 }}
{{- end }}
{{- end -}}

{{/* Render a networking.k8s.io/v1 Ingress. */}}
{{- define "workload.ingress" -}}
{{- $root := .root -}}
{{- $spec := .spec -}}
{{- $name := .name -}}
{{- $serviceName := .serviceName -}}
{{- $servicePort := $spec.servicePort | default $root.Values.service.port -}}
{{- $annotations := deepCopy ($spec.annotations | default dict) -}}
{{- range $annotationName, $computed := ($spec.computedAnnotations | default dict) -}}
{{- if hasKey $annotations $annotationName -}}
{{- fail (printf "ingress annotation %q cannot be set in both annotations and computedAnnotations" $annotationName) -}}
{{- end -}}
{{- $valueFrom := required (printf "computedAnnotations[%q].valueFrom is required" $annotationName) $computed.valueFrom -}}
{{- if eq $valueFrom "serviceName" -}}
{{- $_ := set $annotations $annotationName $serviceName -}}
{{- else -}}
{{- fail (printf "computedAnnotations[%q].valueFrom %q is unsupported" $annotationName $valueFrom) -}}
{{- end -}}
{{- end -}}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ $name }}
  namespace: {{ include "workload.namespace" $root }}
  labels:
    {{- include "workload.labels" $root | nindent 4 }}
  {{- with $annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  {{- with $spec.className }}
  ingressClassName: {{ . }}
  {{- end }}
  {{- with $spec.tls }}
  tls:
    {{- range . }}
    - hosts:
        {{- range .hosts }}
        - {{ . | quote }}
        {{- end }}
      secretName: {{ .secretName }}
    {{- end }}
  {{- end }}
  rules:
    {{- range $spec.hosts }}
    - host: {{ .host | quote }}
      http:
        paths:
          {{- range .paths }}
          - path: {{ .path }}
            {{- with .pathType }}
            pathType: {{ . }}
            {{- end }}
            backend:
              service:
                name: {{ $serviceName }}
                port:
                  number: {{ $servicePort }}
          {{- end }}
    {{- end }}
{{- end -}}
