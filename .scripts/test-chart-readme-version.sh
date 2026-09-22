#!/usr/bin/env bash
# Fails when a chart README advertises a version other than the one the chart will be tagged as.
# A published example that installs a version nobody can pull is worse than no example at all.
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $(basename "$0") <chart-directory>" >&2
    exit 2
fi

CHART_DIR=$1
CHART=$(basename "$CHART_DIR")
CHART_YAML="$CHART_DIR/Chart.yaml"
README="$CHART_DIR/README.md"

for FILE in "$CHART_YAML" "$README"; do
    if [[ ! -f "$FILE" ]]; then
        echo "::error::$FILE is required." >&2
        exit 1
    fi
done

VERSION=$(grep -m1 -oE '^version:[[:space:]]*[^[:space:]]+' "$CHART_YAML" | awk '{print $2}')
if [[ -z "$VERSION" ]]; then
    echo "::error file=$CHART_YAML::Chart version is required." >&2
    exit 1
fi

# Install examples: `helm install ... --version X.Y.Z`.
mapfile -t CLI_VERSIONS < <(
    grep -oE -- '--version[[:space:]]+[0-9]+\.[0-9]+\.[0-9]+[^[:space:]]*' "$README" |
        awk '{print $2}' | sort -u
)

# Dependency examples: a `version:` line following `name: <this chart>`.
mapfile -t DEP_VERSIONS < <(
    awk -v chart="$CHART" '
        $0 ~ ("name:[[:space:]]*" chart "[[:space:]]*$") { pending = 1; next }
        pending && match($0, /version:[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+[^[:space:]]*/) {
            found = substr($0, RSTART, RLENGTH)
            sub(/version:[[:space:]]*/, "", found)
            print found
            pending = 0
        }
    ' "$README" | sort -u
)

FOUND=("${CLI_VERSIONS[@]}" "${DEP_VERSIONS[@]}")

if [[ ${#FOUND[@]} -eq 0 ]]; then
    echo "::error file=$README::No version example found. Document how to install $CHART, pinning --version $VERSION, so the example is covered by this check." >&2
    exit 1
fi

STALE=()
for CANDIDATE in "${FOUND[@]}"; do
    [[ "$CANDIDATE" != "$VERSION" ]] && STALE+=("$CANDIDATE")
done

if [[ ${#STALE[@]} -gt 0 ]]; then
    echo "::error file=$README::References $(printf '%s ' "${STALE[@]}")but $CHART will be tagged $CHART/$VERSION. Update the examples in the same change as Chart.yaml." >&2
    exit 1
fi

echo "$CHART: ${#FOUND[@]} version example(s) match $VERSION"
