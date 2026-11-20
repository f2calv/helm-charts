# Chart Integration Tests

Install the real workload, signalcli and Piper charts together in a disposable kind cluster.
The Helm test checks the workload HTTP Service, signalcli's unregistered API and nonzero PCM audio
from Piper over Wyoming. Default persistent storage is exercised for both application charts.

The GitHub Actions `integration` job uses the same kind action as the shared chart-packaging
workflow. It builds nested local dependencies before the harness, which the packaging workflow's
single dependency-build step cannot do. Release jobs wait for integration success.

Render-only fixtures remain separate: some deliberately reference external Secrets, prepared voice
caches or KEDA resources that are not installed in this cluster.

## Run Locally

Requires Docker, kind and Helm 3. Use the repository's pinned Helm version. Public images and the
default Piper voice are downloaded; no cloud credentials or Signal account registration are needed.
From the repository root in Bash:

```bash
export KUBECONFIG="$(mktemp)"
kind create cluster --name chart-integration --kubeconfig "$KUBECONFIG"
helm dependency build charts/signalcli --skip-refresh
helm dependency build charts/piper --skip-refresh
helm dependency build tests/integration --skip-refresh
helm install integration tests/integration --namespace integration --create-namespace --wait --timeout 10m
helm test integration --namespace integration --timeout 3m --logs
```

After inspecting any failure, remove only the disposable cluster and its temporary kubeconfig:

```bash
kind delete cluster --name chart-integration
rm "$KUBECONFIG"
unset KUBECONFIG
```

Keep the harness dependency versions aligned with the source charts when bumping them. These smoke
tests do not cover every workload kind, autoscaling integration, Signal messaging or voice quality.
