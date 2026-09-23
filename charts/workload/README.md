# Universal workload chart

Deploy common Kubernetes workload kinds through one framework-neutral chart with sensible
defaults.

`workload` is a universal, framework-neutral Helm chart for deploying one
containerised workload without maintaining a large application-specific chart.
Sensible defaults keep common deployments concise, while explicit values expose
the Kubernetes controls needed for stateful services, background jobs,
autoscaling, scheduling, networking, storage, and disruption management.

The same chart supports .NET, Go, Rust, Java, and other containerised runtimes.
Applications supply their image and runtime-specific configuration; the chart
owns the reusable Kubernetes resource structure.

## Install

### Helm

Install the `workload` chart directly from GHCR:

```bash
helm install my-app oci://ghcr.io/f2calv/charts/workload --version 1.0.3 \
  --namespace my-namespace --create-namespace \
  --set replicaCount=1 \
  --set-string image.repository=nginx \
  --set-string image.tag=1.27-alpine
```

Upgrade to the latest stable `workload` chart published in GHCR:

```bash
helm upgrade --install my-app oci://ghcr.io/f2calv/charts/workload \
  --namespace my-namespace --create-namespace \
  --set replicaCount=1 \
  --set-string image.repository=nginx \
  --set-string image.tag=1.27-alpine
```

### Argo CD Application

[Argo CD](https://argo-cd.readthedocs.io/) can consume the same OCI package directly:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
spec:
  project: default
  destination:
    namespace: my-namespace
    server: https://kubernetes.default.svc
  source:
    repoURL: ghcr.io/f2calv
    chart: charts/workload
    targetRevision: 1.0.3
    helm:
      valuesObject:
        replicaCount: 1
        image:
          repository: nginx
          tag: 1.27-alpine
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

## Configuration

### Workload Kinds

Set `kind` to one of the supported primary workload modes:

`Deployment` is the default.

| Value                                                                                   | Resources rendered               | Description                                               |
| --------------------------------------------------------------------------------------- | -------------------------------- | --------------------------------------------------------- |
| [`Deployment`](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)   | Deployment                       | Runs scalable, interchangeable pods with rolling updates. |
| [`DaemonSet`](https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/)     | DaemonSet                        | Runs one pod on every eligible node.                      |
| [`StatefulSet`](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/) | StatefulSet                      | Runs ordered pods with stable identities and storage.     |
| [`ScaledObject`](https://keda.sh/docs/latest/concepts/scaling-deployments/)             | Deployment and KEDA ScaledObject | Adds event-driven autoscaling to a Deployment.            |
| [`CronJob`](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/)       | CronJob                          | Runs a workload on a repeating schedule.                  |
| [`ScaledJob`](https://keda.sh/docs/latest/concepts/scaling-jobs/)                       | KEDA ScaledJob                   | Creates event-driven Jobs that scale with queue demand.   |

Set `job.enabled: true` to render an additional one-shot Job with the same
image, environment, volumes, and scheduling configuration.

### Persistence

Declare PVCs alongside their consuming workload through `persistentVolumeClaims`.
Each claim requires a name, one or more Kubernetes access modes, and a storage
capacity. `storageClassName` is optional so clusters can use their default class.

Set the values through the Helm CLI:

```bash
helm upgrade --install my-app oci://ghcr.io/f2calv/charts/workload \
  --namespace my-namespace --create-namespace \
  --set replicaCount=1 \
  --set-string image.repository=nginx \
  --set-string image.tag=1.27-alpine \
  --set-string 'persistentVolumeClaims[0].name=model-cache' \
  --set-string 'persistentVolumeClaims[0].storageClassName=local-path' \
  --set-string 'persistentVolumeClaims[0].accessModes[0]=ReadWriteOnce' \
  --set-string 'persistentVolumeClaims[0].storage=50Gi' \
  --set-string 'volumes[0].name=models' \
  --set-string 'volumes[0].persistentVolumeClaim.claimName=model-cache' \
  --set-string 'volumeMounts[0].name=models' \
  --set-string 'volumeMounts[0].mountPath=/models'
```

Or set the same values via an Argo CD `valuesObject`:

```yaml
persistentVolumeClaims:
  - name: model-cache
    storageClassName: local-path
    accessModes:
      - ReadWriteOnce
    storage: 50Gi
volumes:
  - name: models
    persistentVolumeClaim:
      claimName: model-cache
volumeMounts:
  - name: models
    mountPath: /models
```

When migrating an existing claim from another GitOps owner, protect the live
resource from pruning and reconcile that protection before transferring the
declaration. Verify the claim UID and bound PV remain unchanged after adoption.

### Default Values

```yaml
# Workload mode and replica behavior.
replicaCount: 0
kind: Deployment
namespaceOverride: ""
serviceName: ""
revisionHistoryLimit: 3
strategy: {}
updateStrategy: {}
volumeClaimTemplates: []
cronJobSchedule: ""
cronJobConcurrencyPolicy: Replace

# Pod execution settings.
restartPolicy: ""
runtimeClassName: ""
hostNetwork: false
dnsPolicy: ""
terminationGracePeriodSeconds: null

# Container image and process.
image:
  repository: busybox
  pullPolicy: IfNotPresent
  tag: ""
imagePullSecrets: []
command: []
args: []

# Resource naming and pod identity.
nameOverride: ""
fullnameOverride: ""
serviceAccount:
  create: false
  automount: true
  annotations: {}
  name: ""
podAnnotations: {}
podLabels: {}
podSecurityContext: {}
securityContext: {}

# Service and ingress networking.
service:
  enabled: true
  name: http
  type: ClusterIP
  port: 80
  containerPort: 80
  protocol: TCP
  annotations: {}
extraPorts: []
ingress:
  enabled: false
  className: ""
  annotations: {}
  servicePort: ""
  hosts:
    - host: example.local
      paths:
        - path: /
          pathType: ImplementationSpecific
  tls: []
extraIngresses: []

# Resources, probes, and lifecycle.
resources: {}
startupProbe: false
readinessProbe: false
livenessProbe: false
lifecycle: {}

# Autoscaling and additional containers.
autoscaling:
  enabled: false
initContainers: []
extraContainers: []

# Storage and pod scheduling.
volumes: []
volumeMounts: []
persistentVolumeClaims: []
configMaps: []
nodeSelector: {}
tolerations: []
affinity: {}
topologySpreadConstraints: []

# Pod disruption budget.
podDisruptionBudget:
  enabled: false
  minAvailable: 1
  maxUnavailable: null
  unhealthyPodEvictionPolicy: ""

# Container environment.
envFieldRef: {}
envVars: {}
envSecrets: {}
envVarsFrom: []

# Optional one-shot job.
job:
  enabled: false
  nameSuffix: job
  annotations: {}
  command: []
  args: []
  env: {}
  resources: {}
  restartPolicy: Never
  ttlSecondsAfterFinished: 360
  backoffLimit: 1

# KEDA settings for ScaledObject and ScaledJob workloads.
keda:
  pollingInterval: 10
  cooldownPeriod: 300
  minReplicaCount: 1
  maxReplicaCount: 2
  databaseIndex: ""
  successfulJobsHistoryLimit: 5
  failedJobsHistoryLimit: 5
  rolloutStrategy: gradual
  jobTargetRef:
    activeDeadlineSeconds: 600
    backoffLimit: 6
  triggers: []
  triggerAuthentications: []
```

## Related Projects

- [Kubernetes](https://kubernetes.io/) provides the workload resources rendered by this chart.
- [KEDA](https://keda.sh/) provides the `ScaledObject` and `ScaledJob` autoscaling resources.
