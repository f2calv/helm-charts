#!/usr/bin/env bash
# Validates opt-in HTTP scaling, ingress namespaces, and invalid chart configurations.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CHART="$REPO_ROOT/charts/workload"
VALUES="$CHART/ci/http-scaling-values.yaml"
RENDERED=$(mktemp)
INVALID_OUTPUT=$(mktemp)
trap 'rm -f "$RENDERED" "$INVALID_OUTPUT"' EXIT

helm template example "$CHART" --namespace example --values "$VALUES" > "$RENDERED"

yq -e '
  select(.kind == "Deployment") |
  .metadata.name == "example-api" and
  .metadata.namespace == "example-app" and
  (.spec | has("replicas") | not)
' "$RENDERED" >/dev/null

yq -e '
  select(.kind == "Service") |
  .metadata.name == "example-api" and
  .metadata.namespace == "example-app" and
  .spec.ports[0].port == 80
' "$RENDERED" >/dev/null

yq -e '
  select(.kind == "InterceptorRoute") |
  .apiVersion == "http.keda.sh/v1beta1" and
  .metadata.name == "example-api" and
  .metadata.namespace == "example-app" and
  .spec.target.service == "example-api" and
  .spec.target.port == 80 and
  .spec.scalingMetric.concurrency.targetValue == 10 and
  .spec.rules[0].paths[0].value == "/api" and
  .spec.timeouts.readiness == "60s" and
  .spec.coldStart.maxPendingRequests == 100
' "$RENDERED" >/dev/null

yq -e '
  select(.kind == "ScaledObject") |
  .metadata.namespace == "example-app" and
  .spec.scaleTargetRef.name == "example-api" and
  .spec.minReplicaCount == 0 and
  .spec.maxReplicaCount == 5 and
  .spec.advanced.horizontalPodAutoscalerConfig.behavior.scaleDown.stabilizationWindowSeconds == 60 and
  (.spec.triggers | length) == 1 and
  .spec.triggers[0].type == "external-push" and
  .spec.triggers[0].metadata.interceptorRoute == "example-api" and
  .spec.triggers[0].metadata.scalerAddress == "keda-add-ons-http-external-scaler.keda:9090"
' "$RENDERED" >/dev/null

for name in example-api-fe5181bd example-api-alternate-5dc1abf7; do
  NAME="$name" yq -e '
    select(.kind == "Ingress" and .metadata.name == strenv(NAME)) |
    .metadata.namespace == "keda" and
    .spec.rules[0].http.paths[0].backend.service.name == "keda-add-ons-http-interceptor-proxy" and
    .spec.rules[0].http.paths[0].backend.service.port.number == 8080
  ' "$RENDERED" >/dev/null
done

yq -e '
  select(.kind == "Ingress" and .metadata.name == "example-api-fe5181bd") |
  .metadata.annotations."example.com/backend-service" == "keda-add-ons-http-interceptor-proxy"
' "$RENDERED" >/dev/null

helm template example "$CHART" --namespace example \
  --values "$CHART/ci/http-scaling-rate-values.yaml" > "$RENDERED"

yq -e '
  select(.kind == "InterceptorRoute") |
  .spec.scalingMetric.requestRate.targetValue == 100 and
  .spec.scalingMetric.requestRate.window == "1m" and
  (.spec.scalingMetric | has("concurrency") | not) and
  .spec.timeouts.request == "0s" and
  .spec.rules[0].headers[0].name == "X-Example"
' "$RENDERED" >/dev/null

yq -e '
  select(.kind == "Ingress") |
  .metadata.name == "example-workload" and
  .metadata.namespace == "example" and
  .spec.rules[0].http.paths[0].backend.service.port.number == 8080
' "$RENDERED" >/dev/null

yq -e '
  select(.kind == "ScaledObject") |
  (.spec.triggers | length) == 2 and
  .spec.triggers[1].type == "prometheus"
' "$RENDERED" >/dev/null

helm template example "$CHART" --namespace example --values "$VALUES" \
  --set keda.http.scalingMetric.requestRate.targetValue=100 > "$RENDERED"
yq -e '
  select(.kind == "InterceptorRoute") |
  .spec.scalingMetric.concurrency.targetValue == 10 and
  .spec.scalingMetric.requestRate.targetValue == 100
' "$RENDERED" >/dev/null

helm template example "$CHART" --namespace example --values "$VALUES" \
  --set keda.http.enabled=false > "$RENDERED"
yq -e '
  select(.kind == "Ingress" and .metadata.name == "example-api") |
  .metadata.namespace == "example-app" and
  .spec.rules[0].http.paths[0].backend.service.name == "example-api" and
  .spec.rules[0].http.paths[0].backend.service.port.number == 80
' "$RENDERED" >/dev/null
if grep -F 'kind: InterceptorRoute' "$RENDERED" >/dev/null; then
  echo "::error::HTTP scaling disabled still rendered an InterceptorRoute" >&2
  exit 1
fi

assert_rejected() {
  local expected=$1
  shift
  if helm template invalid "$CHART" --values "$VALUES" "$@" > "$INVALID_OUTPUT" 2>&1; then
    echo "::error::Expected HTTP scaling configuration to fail: $*" >&2
    exit 1
  fi
  if ! grep -F "$expected" "$INVALID_OUTPUT" >/dev/null; then
    cat "$INVALID_OUTPUT" >&2
    echo "::error::Expected failure to contain: $expected" >&2
    exit 1
  fi
}

for kind in Deployment DaemonSet StatefulSet Job ScaledJob CronJob; do
  assert_rejected 'requires kind: ScaledObject' --set "kind=$kind"
done
assert_rejected 'requires replicaCount > 0' --set replicaCount=0
assert_rejected 'requires autoscaling.enabled: true' --set autoscaling.enabled=false
assert_rejected 'requires an enabled TCP Service' --set service.enabled=false
assert_rejected 'requires an enabled TCP Service' --set service.protocol=UDP
assert_rejected 'must not exceed' --set keda.minReplicaCount=6
assert_rejected 'requires explicit keda.http.rules' --set-json 'keda.http.rules=[]'
assert_rejected 'scalingMetric.concurrency or requestRate' --set-json 'keda.http.scalingMetric={}'
assert_rejected 'must be a non-empty host:port address' --set keda.http.scalerAddress=
assert_rejected 'interceptor.port' --set ingress.servicePort=80
assert_rejected 'interceptor.port' --set extraIngresses[0].servicePort=80
assert_rejected 'targetValue' --set keda.http.scalingMetric.concurrency.targetValue=0
assert_rejected 'targetValue' --set-json 'keda.http.scalingMetric.concurrency={}'
assert_rejected 'requestRate' --set keda.http.scalingMetric.requestRate.targetValue=0
assert_rejected 'readiness' --set keda.http.timeouts.readiness=invalid
assert_rejected 'maxPendingRequests' --set keda.http.coldStart.maxPendingRequests=0
assert_rejected 'port' --set keda.http.interceptor.port=65536
assert_rejected 'enabled' --set-string keda.http.enabled=true
assert_rejected 'unknown' --set keda.http.unknown=true
assert_rejected 'rules' --set-json 'keda.http.rules=[{}]'

echo "HTTP scaling: 4 render scenarios and 25 invalid configurations passed."
