---
title: Universal workload chart
description: Deploy common Kubernetes workload kinds through one framework-neutral chart with sensible defaults
---

## Overview

`workload` is a universal, framework-neutral Helm chart for deploying one
containerised workload without maintaining a large application-specific chart.
Sensible defaults keep common deployments concise, while explicit values expose
the Kubernetes controls needed for stateful services, background jobs,
autoscaling, scheduling, networking, storage, and disruption management.

The same chart supports .NET, Go, Rust, Java, and other containerised runtimes.
Applications supply their image and runtime-specific configuration; the chart
owns the reusable Kubernetes resource structure.

## Workload Kinds

Set `kind` to one of the supported primary workload modes:

| Value         | Resources rendered                      |
|---------------|-----------------------------------------|
| `Deployment`  | Deployment                              |
| `DaemonSet`   | DaemonSet                               |
| `StatefulSet` | StatefulSet                             |
| `ScaledObject`| Deployment and KEDA ScaledObject        |
| `CronJob`     | CronJob                                 |
| `ScaledJob`   | KEDA ScaledJob                          |

Set `job.enabled: true` to render an additional one-shot Job with the same
image, environment, volumes, and scheduling configuration.

## Pod Scheduling

Every pod-producing template supports the same Kubernetes scheduling fields:

* `nodeSelector`
* `tolerations`
* `affinity`
* `topologySpreadConstraints`

Empty defaults omit these fields. The following example constrains operating
system placement and spreads matching pods across nodes:

```yaml
nodeSelector:
  kubernetes.io/os: linux
tolerations:
  - key: dedicated
    operator: Equal
    value: workloads
    effect: NoSchedule
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
        - matchExpressions:
            - key: kubernetes.io/arch
              operator: In
              values: [amd64, arm64]
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: DoNotSchedule
    labelSelector:
      matchLabels:
        app.kubernetes.io/name: workload
```

## Pod Disruption Budgets

PodDisruptionBudget support is opt-in for `Deployment`, `DaemonSet`,
`StatefulSet`, and `ScaledObject`. Enabling it for `CronJob` or `ScaledJob`, or
with `replicaCount: 0`, fails template rendering.

Exactly one availability setting must be configured. The conservative default
uses `minAvailable: 1`:

```yaml
replicaCount: 2
podDisruptionBudget:
  enabled: true
  minAvailable: 1
  unhealthyPodEvictionPolicy: IfHealthyBudget
```

To use `maxUnavailable`, clear the default `minAvailable` value explicitly:

```yaml
replicaCount: 3
podDisruptionBudget:
  enabled: true
  minAvailable: null
  maxUnavailable: 25%
  unhealthyPodEvictionPolicy: AlwaysAllow
```

Availability values accept non-negative integers or percentages from `0%` to
`100%`. `unhealthyPodEvictionPolicy` may be `IfHealthyBudget` or `AlwaysAllow`.
