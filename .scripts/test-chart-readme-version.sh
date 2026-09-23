#!/usr/bin/env bash
# Fails when chart-specific or repository README references differ from the chart version.
# A published example that installs a version nobody can pull is worse than no example at all.
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "usage: $(basename "$0") <chart-directory> <repository-readme>" >&2
    exit 2
fi

CHART_DIR=$1
REPOSITORY_README=$2
CHART=$(basename "$CHART_DIR")
CHART_YAML="$CHART_DIR/Chart.yaml"
README="$CHART_DIR/README.md"

for FILE in "$CHART_YAML" "$README" "$REPOSITORY_README"; do
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

collect_example_versions() {
    local readme=$1

    {
        # Install examples: `helm install .../<chart> --version X.Y.Z`.
        awk -v chart="$CHART" '
            $0 ~ /helm install/ && $0 ~ ("/" chart "([[:space:]]|$)") &&
                match($0, /--version[[:space:]]+[0-9]+\.[0-9]+\.[0-9]+[^[:space:]]*/) {
                found = substr($0, RSTART, RLENGTH)
                sub(/--version[[:space:]]+/, "", found)
                print found
            }
        ' "$readme"

        # Dependency examples: a `version:` line following `name: <this chart>`.
        awk -v chart="$CHART" '
            $0 ~ ("name:[[:space:]]*" chart "[[:space:]]*$") { pending = 1; next }
            pending && match($0, /version:[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+[^[:space:]]*/) {
                found = substr($0, RSTART, RLENGTH)
                sub(/version:[[:space:]]*/, "", found)
                print found
                pending = 0
            }
        ' "$readme"

        # Argo CD examples: a `targetRevision:` following `chart: charts/<this chart>`.
        awk -v chart="$CHART" '
            $0 ~ ("chart:[[:space:]]*charts/" chart "[[:space:]]*$") { pending = 1; next }
            pending && match($0, /targetRevision:[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+[^[:space:]]*/) {
                found = substr($0, RSTART, RLENGTH)
                sub(/targetRevision:[[:space:]]*/, "", found)
                print found
                pending = 0
            }
        ' "$readme"
    } | sort -u
}

validate_versions() {
    local readme=$1
    local description=$2
    shift 2
    local -a found=("$@")
    local -a stale=()

    if [[ ${#found[@]} -eq 0 ]]; then
        echo "::error file=$readme::No $CHART version found in the $description." >&2
        exit 1
    fi

    for candidate in "${found[@]}"; do
        [[ "$candidate" != "$VERSION" ]] && stale+=("$candidate")
    done

    if [[ ${#stale[@]} -gt 0 ]]; then
        echo "::error file=$readme::References $(printf '%s ' "${stale[@]}")but $CHART will be tagged $CHART/$VERSION. Update the $description in the same change as Chart.yaml." >&2
        exit 1
    fi

    echo "$CHART: ${#found[@]} version reference(s) in the $description match $VERSION"
}

mapfile -t CHART_README_VERSIONS < <(collect_example_versions "$README")

mapfile -t REPOSITORY_VERSIONS < <(
    {
        collect_example_versions "$REPOSITORY_README"

        # Catalogue row: the version cell on the row linking to this chart's README.
        awk -v chart_readme="charts/$CHART/README.md" '
            index($0, "](" chart_readme ")") &&
                match($0, /`[0-9]+\.[0-9]+\.[0-9]+[^`]*`/) {
                found = substr($0, RSTART + 1, RLENGTH - 2)
                print found
            }
        ' "$REPOSITORY_README"
    } | sort -u
)

validate_versions "$README" "chart README" "${CHART_README_VERSIONS[@]}"
validate_versions "$REPOSITORY_README" "repository README" "${REPOSITORY_VERSIONS[@]}"
