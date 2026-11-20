# Helm charts

Helm charts for Kubernetes operators: reusable container workloads and application-specific
wrappers for Signal messaging and Wyoming text-to-speech. Charts are distributed as OCI packages.

## Chart Catalogue

| Chart | Latest version | OCI reference | Purpose |
| --- | --- | --- | --- |
| [signalcli](charts/signalcli/README.md) | `1.2.0` | `oci://ghcr.io/f2calv/charts/signalcli` | Deploys [signal-cli-rest-api](https://github.com/bbernhard/signal-cli-rest-api) with persistent account state, compatible probes, JVM-sized resources, and validated environment variables. |
| [workload](charts/workload/README.md) | `1.7.0` | `oci://ghcr.io/f2calv/charts/workload` | Deploys common Kubernetes workload kinds with opt-in operational controls and KEDA HTTP scaling. |
| [piper](charts/piper/README.md) | `0.1.0` | `oci://ghcr.io/f2calv/charts/piper` | LinuxServer Piper with a Wyoming TCP service, voice cache, TCP probes and validated environment settings. |

Browse the public [workload package](https://github.com/f2calv/helm-charts/pkgs/container/charts%2Fworkload),
[signalcli package](https://github.com/f2calv/helm-charts/pkgs/container/charts%2Fsignalcli)
or [piper package](https://github.com/f2calv/helm-charts/pkgs/container/charts%2Fpiper).

## Quick Start

With an OCI-capable Helm client and a Kubernetes context, install a single HTTP workload:

```bash
helm install my-app oci://ghcr.io/f2calv/charts/workload --version 1.7.0 \
  --namespace my-namespace --create-namespace \
  --set replicaCount=1 \
  --set-string image.repository=nginx \
  --set-string image.tag=1.27-alpine
```

This creates a Deployment and ClusterIP Service. No Helm repository registration or GHCR login
is required to pull these public charts. Pin the chart version and set your own image tag;
the workload default is zero replicas, not a runnable application.

Use the chart READMEs for Argo CD examples, values, persistence and mode-specific prerequisites.
The signalcli chart additionally needs a default or explicitly selected StorageClass and account
registration/linking after installation.

## Dependency Graph

Application wrappers bundle their exact workload dependency. Installing a published package does
not require checking out this repository.

```mermaid
graph LR
  Signal(["signalcli 1.2.0"]) -->|bundled dependency, alias signalcli| Workload["workload 1.7.0"]
  Piper(["piper 0.1.0"]) -->|bundled dependency, alias piper| Workload
  Consumer([Your container]) -->|image and values| Workload
  Workload --> Resources[Kubernetes resources]
  classDef owned fill:#dbeafe,stroke:#1d4ed8,color:#1e3a8a
  class Signal,Piper,Workload owned
```

## Version Selection

Each chart has an independent version, defined in
[signalcli Chart.yaml](charts/signalcli/Chart.yaml),
[piper Chart.yaml](charts/piper/Chart.yaml) and
[workload Chart.yaml](charts/workload/Chart.yaml). OCI tags use the bare chart version;
source release tags use `<chart>/<version>`. A chart version is not its container image version.
The signalcli dependency is pinned in its [Chart.lock](charts/signalcli/Chart.lock).

## License

This project is released under the [MIT License](LICENSE).
