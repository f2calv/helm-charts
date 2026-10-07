#!/usr/bin/env bash
# Validates workload-owned policies, common identity, and pod token controls.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CHART="$REPO_ROOT/charts/workload"
DEPLOYMENT_VALUES="$CHART/ci/deployment-values.yaml"
RENDERED=$(mktemp)
INVALID_OUTPUT=$(mktemp)
trap 'rm -f "$RENDERED" "$INVALID_OUTPUT"' EXIT

helm template example "$CHART" \
  --namespace example \
  --values "$DEPLOYMENT_VALUES" > "$RENDERED"

yq -e '
  select(.kind == "Deployment" and .metadata.name == "example-workload") |
  .metadata.labels."app.kubernetes.io/component" == "web" and
  .spec.template.metadata.labels."app.kubernetes.io/component" == "web" and
  .spec.template.spec.automountServiceAccountToken == false and
  .spec.template.spec.containers[0].name == "app"
' "$RENDERED" >/dev/null

yq -e '
  select(.kind == "NetworkPolicy" and .metadata.name == "allow-ingress") |
  .metadata.namespace == "example" and
  .metadata.labels."app.kubernetes.io/component" == "web" and
  .spec.policyTypes[0] == "Ingress"
' "$RENDERED" >/dev/null

for fixture in cronjob-values.yaml job-values.yaml scaledjob-values.yaml; do
  helm template example "$CHART" \
    --namespace example \
    --values "$CHART/ci/$fixture" \
    --set automountServiceAccountToken=false > "$RENDERED"
  grep -F 'automountServiceAccountToken: false' "$RENDERED" >/dev/null
done

if helm template invalid "$CHART" \
  --set replicaCount=1 \
  --set image.repository=busybox \
  --set-string 'networkPolicies[0].name=broken' > "$INVALID_OUTPUT" 2>&1; then
  echo "expected a NetworkPolicy without spec to fail schema validation" >&2
  exit 1
fi

grep -F "missing property 'spec'" "$INVALID_OUTPUT" >/dev/null
