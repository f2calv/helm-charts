#!/usr/bin/env bash
# Checks the Piper wrapper's environment, TCP probes, persistence, schema and package contract.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CHART="$REPO_ROOT/charts/piper"
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

assert_rendered() {
  local expression=$1
  yq eval-all -e "$expression" "$TEMP_DIR/rendered.yaml" >/dev/null
}

helm dependency build "$CHART" --skip-refresh
helm template example "$CHART" --namespace example > "$TEMP_DIR/rendered.yaml"
assert_rendered 'select(.kind == "Deployment") | .spec.strategy.type == "Recreate"'
assert_rendered 'select(.kind == "Deployment") | .spec.template.spec.containers[0] |
  ((.startupProbe.tcpSocket.port == "wyoming") and (.readinessProbe.tcpSocket.port == "wyoming") and
  (.livenessProbe == null) and (.ports[0].containerPort == 10200))'
assert_rendered 'select(.kind == "Deployment") | .spec.template.spec.containers[0].env[] |
  select(.name == "PIPER_VOICE") | .value == "en_US-lessac-medium"'
assert_rendered 'select(.kind == "Deployment") | .spec.template.spec.containers[0].volumeMounts[] |
  select(.name == "voices") | .mountPath == "/config"'
assert_rendered 'select(.kind == "Service") | .spec.ports[0] |
  ((.port == 10200) and (.targetPort == 10200) and (.protocol == "TCP"))'
assert_rendered 'select(.kind == "PersistentVolumeClaim") |
  ((.metadata.name == "piper-data") and (.spec.accessModes[0] == "ReadWriteOnce"))'
assert_rendered '[.] | map(select(.kind == "Ingress" or .kind == "Secret")) | length == 0'

for fixture in "$CHART"/ci/*-values.yaml; do
  helm lint "$CHART" --strict --values "$fixture"
  helm template example "$CHART" --namespace example --values "$fixture" > "$TEMP_DIR/rendered.yaml"
  case "$(basename "$fixture")" in
    ephemeral-values.yaml)
      assert_rendered '[.] | map(select(.kind == "PersistentVolumeClaim")) | length == 0'
      assert_rendered 'select(.kind == "Deployment") | .spec.template.spec.volumes[] |
        select(.name == "voices") | has("emptyDir")'
      ;;
    existing-claim-values.yaml)
      assert_rendered '[.] | map(select(.kind == "PersistentVolumeClaim")) | length == 0'
      assert_rendered 'select(.kind == "Deployment") | .spec.template.spec.volumes[] |
        select(.name == "voices") | .persistentVolumeClaim.claimName == "existing-voice-cache"'
      assert_rendered 'select(.kind == "Deployment") | .spec.template.spec.containers[0].env[] |
        select(.name == "LOCAL_ONLY") | .value == "true"'
      assert_rendered 'select(.kind == "Deployment") | .spec.template.spec.containers[0].env[] |
        select(.name == "NO_STREAMING") | .value == ""'
      ;;
  esac
done

for fixture in "$CHART"/tests/invalid/*.yaml; do
  if helm template invalid "$CHART" --values "$fixture" > "$TEMP_DIR/invalid.txt" 2>&1; then
    echo "::error::Expected schema rejection for $(basename "$fixture")." >&2
    exit 1
  fi
  grep -F 'piper' "$TEMP_DIR/invalid.txt" >/dev/null
  grep -F 'schema' "$TEMP_DIR/invalid.txt" >/dev/null
  case "$(basename "$fixture")" in
    empty-voice.yaml) field=PIPER_VOICE ;;
    false-local-only.yaml) field=LOCAL_ONLY ;;
    false-no-streaming.yaml) field=NO_STREAMING ;;
    http-ingress.yaml) field=enabled ;;
    zero-length.yaml) field=PIPER_LENGTH ;;
    *) echo "::error::Missing expected schema field for $fixture." >&2; exit 1 ;;
  esac
  grep -F "$field" "$TEMP_DIR/invalid.txt" >/dev/null
done

helm template disabled "$CHART" --set piper.replicaCount=0 > "$TEMP_DIR/rendered.yaml"
assert_rendered '[.] | map(select(.kind == "Deployment" or .kind == "Service")) | length == 0'

helm package "$CHART" --destination "$TEMP_DIR"
version=$(yq -r '.version' "$CHART/Chart.yaml")
tar -tzf "$TEMP_DIR/piper-$version.tgz" > "$TEMP_DIR/contents.txt"
grep -F 'piper/charts/workload/Chart.yaml' "$TEMP_DIR/contents.txt" >/dev/null
if grep -E '^piper/(ci|tests)/' "$TEMP_DIR/contents.txt"; then
  echo "::error::Piper package must not include validation fixtures." >&2
  exit 1
fi

bash "$REPO_ROOT/.scripts/test-chart-readme-version.sh" "$CHART" "$REPO_ROOT/README.md"
echo "Piper: default, ephemeral, existing-claim, disabled, 5 invalid fixtures and package checks passed."
