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
{{- /* The deployed image tag, without any @sha256 digest and reduced to label-safe characters. */}}
{{- $tag := splitList "@" (.Values.image.tag | default .Chart.AppVersion | toString) | first }}
{{- with regexReplaceAll "[^-A-Za-z0-9_.]" $tag "_" | trunc 63 | trimAll "-_." }}
app.kubernetes.io/version: {{ . | quote }}
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

{{/* Render literal, referenced, and bulk-imported container environment variables. */}}
{{- define "workload.environment" -}}
{{- $seen := dict -}}
{{- $entries := list -}}
{{- range $name, $fieldPath := .Values.envFieldRef -}}
{{- if hasKey $seen $name -}}
{{- fail (printf "environment variable %q is configured more than once" $name) -}}
{{- end -}}
{{- $_ := set $seen $name true -}}
{{- $entries = append $entries (dict "name" $name "valueFrom" (dict "fieldRef" (dict "fieldPath" $fieldPath))) -}}
{{- end -}}
{{- range $name, $value := .Values.envVars -}}
{{- if hasKey $seen $name -}}
{{- fail (printf "environment variable %q is configured more than once" $name) -}}
{{- end -}}
{{- $_ := set $seen $name true -}}
{{- $entries = append $entries (dict "name" $name "value" (printf "%v" $value)) -}}
{{- end -}}
{{- range $name, $secret := .Values.envSecrets -}}
{{- if hasKey $seen $name -}}
{{- fail (printf "environment variable %q is configured more than once" $name) -}}
{{- end -}}
{{- $_ := set $seen $name true -}}
{{- $entries = append $entries (dict "name" $name "valueFrom" (dict "secretKeyRef" (dict "name" $secret "key" $name))) -}}
{{- end -}}
{{- range $name, $source := .Values.envVarsValueFrom -}}
{{- if hasKey $seen $name -}}
{{- fail (printf "environment variable %q is configured more than once" $name) -}}
{{- end -}}
{{- $_ := set $seen $name true -}}
{{- $entries = append $entries (dict "name" $name "valueFrom" $source) -}}
{{- end -}}
{{- with $entries }}
env:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.envVarsFrom }}
envFrom:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end -}}

{{/* Render a networking.k8s.io/v1 Ingress. */}}
{{- define "workload.ingress" -}}
{{- $root := .root -}}
{{- $spec := .spec -}}
{{- $name := .name -}}
{{- $serviceName := .serviceName -}}
{{- $servicePort := $spec.servicePort | default $root.Values.service.port -}}
{{- $namespace := include "workload.namespace" $root -}}
{{- if $root.Values.keda.http.enabled -}}
{{- $interceptor := $root.Values.keda.http.interceptor -}}
{{- $serviceName = $interceptor.serviceName -}}
{{- $servicePort = $interceptor.port -}}
{{- $namespace = default $namespace $interceptor.namespace -}}
{{- if and $spec.servicePort (ne (int $spec.servicePort) (int $servicePort)) -}}
{{- fail "HTTP-scaled ingress.servicePort must be empty or match keda.http.interceptor.port" -}}
{{- end -}}
{{- if ne $namespace (include "workload.namespace" $root) -}}
{{- $identity := printf "%s/%s" (include "workload.namespace" $root) $name -}}
{{- $name = printf "%s-%s" ($name | trunc 54 | trimSuffix "-") ($identity | sha256sum | trunc 8) -}}
{{- end -}}
{{- end -}}
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
  namespace: {{ $namespace }}
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

{{- define "workload.validateHttpScaling" -}}
{{- if .Values.keda.http.enabled -}}
{{- if ne .Values.kind "ScaledObject" -}}
{{- fail "keda.http.enabled requires kind: ScaledObject" -}}
{{- end -}}
{{- if le (int .Values.replicaCount) 0 -}}
{{- fail "keda.http.enabled requires replicaCount > 0 to render the Deployment and Service; use keda.minReplicaCount: 0 for scale-to-zero" -}}
{{- end -}}
{{- if not .Values.autoscaling.enabled -}}
{{- fail "keda.http.enabled requires autoscaling.enabled: true so KEDA owns Deployment replicas" -}}
{{- end -}}
{{- if or (not .Values.service.enabled) (ne .Values.service.protocol "TCP") -}}
{{- fail "keda.http.enabled requires an enabled TCP Service" -}}
{{- end -}}
{{- if gt (int .Values.keda.minReplicaCount) (int .Values.keda.maxReplicaCount) -}}
{{- fail "keda.minReplicaCount must not exceed keda.maxReplicaCount" -}}
{{- end -}}
{{- if not .Values.keda.http.rules -}}
{{- fail "keda.http.enabled requires explicit keda.http.rules" -}}
{{- end -}}
{{- if not .Values.keda.http.scalingMetric -}}
{{- fail "keda.http.enabled requires keda.http.scalingMetric.concurrency or requestRate" -}}
{{- end -}}
{{- if not (regexMatch `^\S+:[0-9]+$` .Values.keda.http.scalerAddress) -}}
{{- fail "keda.http.scalerAddress must be a non-empty host:port address" -}}
{{- end -}}
{{- end -}}
{{- end -}}
