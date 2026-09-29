#!/usr/bin/env bash
# Validates computed ingress annotations and duplicate-key failures for the workload chart.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CHART="$REPO_ROOT/charts/workload"
COMPUTED_VALUES="$CHART/ci/computed-ingress-annotations-values.yaml"
DUPLICATE_VALUES="$REPO_ROOT/.scripts/fixtures/duplicate-computed-ingress-annotation-values.yaml"
RENDERED=$(mktemp)
DUPLICATE_OUTPUT=$(mktemp)
trap 'rm -f "$RENDERED" "$DUPLICATE_OUTPUT"' EXIT

helm template example "$CHART" \
  --namespace example \
  --values "$COMPUTED_VALUES" > "$RENDERED"

for ingress in example-workload example-workload-streaming; do
  yq -e "
    select(.kind == \"Ingress\" and .metadata.name == \"$ingress\") |
    .metadata.annotations.\"nginx.org/mergeable-ingress-type\" == \"minion\"
  " "$RENDERED" >/dev/null
done

yq -e '
  select(.kind == "Ingress" and .metadata.name == "example-workload") |
  .metadata.annotations."nginx.org/grpc-services" == "example-workload"
' "$RENDERED" >/dev/null

yq -e '
  select(.kind == "Ingress" and .metadata.name == "example-workload-streaming") |
  .metadata.annotations."example.com/backend-service" == "example-workload"
' "$RENDERED" >/dev/null

if helm template duplicate "$CHART" \
  --namespace example \
  --values "$DUPLICATE_VALUES" > "$DUPLICATE_OUTPUT" 2>&1; then
  echo "expected duplicate ingress annotations to fail rendering" >&2
  exit 1
fi

grep -F \
  'ingress annotation "example.com/backend-service" cannot be set in both annotations and computedAnnotations' \
  "$DUPLICATE_OUTPUT" >/dev/null
