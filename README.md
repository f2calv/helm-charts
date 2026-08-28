---
title: Helm charts
description: Shared Helm charts published as public OCI packages for Kubernetes workloads
---

## Overview

This repository contains reusable Helm charts maintained by f2calv. Each chart
has an independent version and is published as a public OCI package in GitHub
Container Registry.

## Chart Catalogue

| Chart      | OCI reference                                  | Purpose                                  |
|------------|------------------------------------------------|------------------------------------------|
| `workload` | `oci://ghcr.io/f2calv/charts/workload`         | Deploy a single containerised workload   |

## Helm Dependency

Reference the chart from an umbrella chart with its published version:

```yaml
dependencies:
  - name: workload
    version: 1.0.0
    repository: oci://ghcr.io/f2calv/charts
    alias: api
```

Resolve the dependency from the umbrella chart directory:

```bash
helm dependency update
```

## Argo CD Application

Argo CD can consume the same OCI package directly:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: example
  namespace: argocd
spec:
  project: default
  destination:
    namespace: example
    server: https://kubernetes.default.svc
  source:
    repoURL: ghcr.io/f2calv
    chart: charts/workload
    targetRevision: 1.0.0
    helm:
      valuesObject:
        kind: Deployment
        replicaCount: 1
        image:
          repository: ghcr.io/example/example
          tag: 1.0.0
          pullPolicy: IfNotPresent
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

## Versioning

The `version` field in each chart's `Chart.yaml` is the source of truth for its
release. Chart versions advance independently, and Git tags use the
`<chart>/<version>` format, for example `workload/1.0.0`. OCI package versions
use the bare semantic version, for example `1.0.0`.

## Deployment Flow

```mermaid
flowchart LR
  Source["charts/&lt;chart&gt;/Chart.yaml"] --> Version["Read chart version"]
  Version --> Tag["Create &lt;chart&gt;/&lt;version&gt; tag"]
  Version --> Package["Package chart"]
  Package --> Registry[("GHCR OCI package")]
  Registry --> Consumers["Helm and Argo CD consumers"]
```
