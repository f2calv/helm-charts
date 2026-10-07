#!/usr/bin/env bash
# Validates optional CronJob deadline and history controls for the workload chart.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CHART="$REPO_ROOT/charts/workload"
CRONJOB_VALUES="$CHART/ci/cronjob-values.yaml"
RENDERED=$(mktemp)
DEFAULT_RENDERED=$(mktemp)
INVALID_OUTPUT=$(mktemp)
trap 'rm -f "$RENDERED" "$DEFAULT_RENDERED" "$INVALID_OUTPUT"' EXIT

helm template example "$CHART" \
  --namespace example \
  --values "$CRONJOB_VALUES" > "$RENDERED"

yq -e '
  select(.kind == "CronJob") |
  .spec.startingDeadlineSeconds == 60 and
  .spec.successfulJobsHistoryLimit == 3 and
  .spec.failedJobsHistoryLimit == 2
' "$RENDERED" >/dev/null

helm template defaults "$CHART" \
  --set kind=CronJob \
  --set-string cronJobSchedule='0 * * * *' > "$DEFAULT_RENDERED"

yq -e '
  select(.kind == "CronJob") |
  (.spec | has("startingDeadlineSeconds") | not) and
  .spec.successfulJobsHistoryLimit == 3 and
  .spec.failedJobsHistoryLimit == 1
' "$DEFAULT_RENDERED" >/dev/null

if helm template invalid "$CHART" \
  --set kind=CronJob \
  --set-string cronJobSchedule='0 * * * *' \
  --set cronJobFailedJobsHistoryLimit=-1 > "$INVALID_OUTPUT" 2>&1; then
  echo "expected a negative CronJob history limit to fail schema validation" >&2
  exit 1
fi

grep -F 'cronJobFailedJobsHistoryLimit' "$INVALID_OUTPUT" >/dev/null
grep -F 'minimum' "$INVALID_OUTPUT" >/dev/null
