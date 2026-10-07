#!/usr/bin/env bash
# Validates literal, referenced, and bulk-imported workload environment values.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CHART="$REPO_ROOT/charts/workload"
ENVIRONMENT_VALUES="$CHART/ci/environment-values.yaml"
RENDERED=$(mktemp)
MODE_RENDERED=$(mktemp)
DUPLICATE_OUTPUT=$(mktemp)
INVALID_OUTPUT=$(mktemp)
trap 'rm -f "$RENDERED" "$MODE_RENDERED" "$DUPLICATE_OUTPUT" "$INVALID_OUTPUT"' EXIT

assert_container() {
  local expression=$1
  yq -e "
    select(.kind == \"Deployment\") |
    .spec.template.spec.containers[0] |
    $expression
  " "$RENDERED" >/dev/null
}

helm template example "$CHART" \
  --namespace example \
  --values "$ENVIRONMENT_VALUES" > "$RENDERED"

assert_container '.env[] | select(.name == "ENABLED") | .value == "true"'
assert_container '.env[] | select(.name == "LOG_LEVEL") | .value == "info"'
assert_container '.env[] | select(.name == "RETRIES") | .value == "3"'
assert_container '.env[] | select(.name == "POD_NAME") | .valueFrom.fieldRef.fieldPath == "metadata.name"'
assert_container '.env[] | select(.name == "API_TOKEN") | (.valueFrom.secretKeyRef.name == "api-secret" and .valueFrom.secretKeyRef.key == "API_TOKEN")'
assert_container '.env[] | select(.name == "CONFIG_VALUE") | (.valueFrom.configMapKeyRef.name == "app-config" and .valueFrom.configMapKeyRef.key == "setting" and .valueFrom.configMapKeyRef.optional == true)'
assert_container '.env[] | select(.name == "CPU_LIMIT") | (.valueFrom.resourceFieldRef.containerName == "app" and .valueFrom.resourceFieldRef.resource == "limits.cpu" and .valueFrom.resourceFieldRef.divisor == "1m")'
assert_container '.env[] | select(.name == "DB_PASSWORD") | (.valueFrom.secretKeyRef.name == "database" and .valueFrom.secretKeyRef.key == "password")'
assert_container '.env[] | select(.name == "NODE_NAME") | .valueFrom.fieldRef.fieldPath == "spec.nodeName"'
assert_container '(.envFrom[0].prefix == "CONFIG_" and .envFrom[0].configMapRef.name == "shared-config")'
assert_container '(.envFrom[1].secretRef.name == "shared-secret" and .envFrom[1].secretRef.optional == true)'

for kind in Job CronJob ScaledJob; do
  extra_args=()
  if [[ "$kind" == "CronJob" ]]; then
    extra_args+=(--set-string 'cronJobSchedule=0 * * * *')
  fi
  helm template example "$CHART" \
    --namespace example \
    --values "$ENVIRONMENT_VALUES" \
    --set "kind=$kind" \
    "${extra_args[@]}" > "$MODE_RENDERED"
  grep -F 'name: DB_PASSWORD' "$MODE_RENDERED" >/dev/null
  grep -F 'secretKeyRef:' "$MODE_RENDERED" >/dev/null
done

if helm template duplicate "$CHART" \
  --values "$ENVIRONMENT_VALUES" \
  --set-string envVars.POD_NAME=duplicate > "$DUPLICATE_OUTPUT" 2>&1; then
  echo "expected duplicate environment variable names to fail rendering" >&2
  exit 1
fi

grep -F 'environment variable "POD_NAME" is configured more than once' "$DUPLICATE_OUTPUT" >/dev/null

if helm template invalid "$CHART" \
  --set-string envVarsValueFrom.INVALID.fieldRef.fieldPath=metadata.name \
  --set-string envVarsValueFrom.INVALID.secretKeyRef.name=example \
  --set-string envVarsValueFrom.INVALID.secretKeyRef.key=value > "$INVALID_OUTPUT" 2>&1; then
  echo "expected an EnvVarSource with multiple source types to fail schema validation" >&2
  exit 1
fi

grep -F 'envVarsValueFrom/INVALID' "$INVALID_OUTPUT" >/dev/null
