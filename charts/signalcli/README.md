# signalcli

Deploys the [bbernhard/signal-cli-rest-api](https://github.com/bbernhard/signal-cli-rest-api)
container, a REST and JSON-RPC wrapper around [signal-cli](https://github.com/AsamK/signal-cli).

The upstream project ships no Helm chart. This one supplies the parts that are easy to get wrong:
a volume for account state, probes that match what the image actually exposes, resources sized for
a JVM, and schema validation of the environment variables that change its behaviour.

The chart depends on [`workload`](../workload/README.md), pulled from `oci://ghcr.io/f2calv/charts`.
Everything under `signalcli` is passed to that subchart, so its keys are the workload chart's keys.

## Install

### Helm

Install the application-specific `signalcli` chart directly from GHCR:

```bash
helm install signalcli oci://ghcr.io/f2calv/charts/signalcli --version 1.0.0 \
  --namespace my-namespace --create-namespace \
  --set-string signalcli.envVars.MODE=json-rpc \
  --set-string signalcli.envVars.LOG_LEVEL=info
```

Upgrade to the latest stable `signalcli` chart published in GHCR:

```bash
helm upgrade --install signalcli oci://ghcr.io/f2calv/charts/signalcli \
  --namespace my-namespace --create-namespace \
  --set-string signalcli.envVars.MODE=json-rpc \
  --set-string signalcli.envVars.LOG_LEVEL=info
```

### Argo CD Application

[Argo CD](https://argo-cd.readthedocs.io/) can consume the same OCI package directly:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: signalcli
  namespace: argocd
spec:
  project: default
  destination:
    namespace: my-namespace
    server: https://kubernetes.default.svc
  source:
    repoURL: ghcr.io/f2calv
    chart: charts/signalcli
    targetRevision: 1.0.0
    helm:
      valuesObject:
        signalcli:
          envVars:
            MODE: json-rpc
            LOG_LEVEL: info
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

## Setup

The container is useless until a Signal account is
registered or linked to it, and that state must land on the persistent volume.

1. Port-forward the service:

   ```bash
    kubectl port-forward --namespace my-namespace svc/signalcli 8080:80
   ```

2. Link as a secondary device to an existing Signal account — the simpler route:

   ```bash
   curl 'http://localhost:8080/v1/qrcodelink?device_name=signalcli'
   ```

   That returns a QR code image. Scan it from Signal on your phone under
   **Settings → Linked devices**.

3. Or register the number outright, which requires solving a captcha and receiving an SMS or voice
   code. See the upstream documentation, as the captcha flow changes periodically.

4. Confirm the account is registered:

   ```bash
   curl http://localhost:8080/v1/accounts
   ```

Account state is written to `/home/.local/share/signal-cli`. If that path is not backed by a
volume, every restart discards the registration and you start again.

## Configuration

| Value | Default | Notes |
| --- | --- | --- |
| `signalcli.replicaCount` | `1` | Capped at one because one registered device owns one state volume |
| `signalcli.image.tag` | `0.100` | Pinned because an empty tag falls back to the workload chart's `appVersion` |
| `signalcli.envVars.MODE` | `json-rpc` | Also decides the receive endpoint's shape |
| `signalcli.envVars.LOG_LEVEL` | `info` | |
| `signalcli.startupProbe` | `/v1/about` | Allows the JVM up to five minutes to load account state |
| `signalcli.readinessProbe` | `/v1/about` | Marks the pod ready when it can serve requests |
| `signalcli.livenessProbe` | `false` | Avoids restarting a slow or busy JVM and disconnecting clients |
| `signalcli.persistentVolumeClaims` | 512Mi `ReadWriteOnce` | Set to `[]` for an ephemeral install |

Environment variables keep their upstream names verbatim, so each traces directly back to the
[bbernhard documentation](https://github.com/bbernhard/signal-cli-rest-api). The map stays
**open**: a variable added by a newer image release can be
set immediately, without waiting for a chart release. Every variable the image documents is
validated, so a bad value fails the install rather than the pod:

```text
Error: values don't meet the specifications of the schema(s) in the following chart(s):
- at '/signalcli/envVars/MODE': value must be one of 'normal', 'native', 'json-rpc', 'json-rpc-native'
```

### Validated environment variables

| Variable | Accepted | Upstream default |
| --- | --- | --- |
| `MODE` | `normal`, `native`, `json-rpc`, `json-rpc-native` | `normal` |
| `AUTO_RECEIVE_SCHEDULE` | five-field cron expression | unset |
| `LOG_LEVEL` | `debug`, `info`, `warn`, `error` | `info` |
| `DEFAULT_SIGNAL_TEXT_MODE` | `normal`, `styled` | `normal` |
| `PORT` | 1–65535 | `8080` |
| `SIGNAL_CLI_CONFIG_DIR` | absolute path | `/home/.local/share/signal-cli/` |
| `SIGNAL_CLI_UID` | unsigned integer | `1000` |
| `SIGNAL_CLI_GID` | unsigned integer | `1000` |
| `SIGNAL_CLI_CHOWN_ON_STARTUP` | boolean | `true` |
| `JSON_RPC_IGNORE_ATTACHMENTS` | boolean | `false` |
| `JSON_RPC_IGNORE_STORIES` | boolean | `false` |
| `JSON_RPC_IGNORE_AVATARS` | boolean | `false` |
| `JSON_RPC_IGNORE_STICKERS` | boolean | `false` |
| `JSON_RPC_TRUST_NEW_IDENTITIES` | `on-first-use`, `always`, `never` | `on-first-use` |
| `SWAGGER_HOST` | non-empty string | `SWAGGER_IP:PORT` |
| `SWAGGER_IP` | non-empty string | container IP |
| `SWAGGER_USE_HTTPS_AS_PREFERRED_SCHEME` | boolean | `false` |

Booleans accept either YAML form, `true` or `"true"`, because the workload chart quotes every value
before it reaches the container. The same applies to the numeric variables.

Three of these are not independent, and the schema cannot enforce that for you:

- **`PORT`** is addressed directly by `service.containerPort` and by both probes. Change it alone
  and the service routes nowhere while the probes fail the pod.
- **`SIGNAL_CLI_CONFIG_DIR`** must match `volumeMounts[0].mountPath`. Change it alone and the
  registration is written outside the volume, so it survives until the next restart and no longer.
- **`AUTO_RECEIVE_SCHEDULE`** applies to `normal` and `native` mode only, and must not be set while
  anything reads messages through the API. `receive` drains the queue from the Signal server, so
  whichever caller arrives second gets nothing.

## Persistence

Account state is small and grows slowly. A volume carrying a linked account for five months held:

```text
17M total
 9.1M  data/<account>.d     message and session database
 7.6M  stickers             downloaded sticker packs
 120K  avatars
  56K  attachments
 4.0K  data/<account>       account JSON, including the private keys
```

The default request is 512Mi, comfortably more than that needs, for three reasons: a PVC can be
grown but never shrunk, filesystem overhead is a punitive share of a very small volume, and many
dynamic provisioners round anything below 1Gi up regardless. Sticker packs are the one component
that grows without bound — set `JSON_RPC_IGNORE_STICKERS: true` if that matters more than fidelity.

`storageClassName` is left unset so a clean install works anywhere, which means the cluster default
is used. **Set it explicitly for anything you intend to keep.** A cluster can carry more than one
default StorageClass, in which case the most recently created one wins, and you can silently land
on a class that is neither replicated nor expandable. Set it through an Argo CD `valuesObject`:

```bash
helm upgrade --install signalcli oci://ghcr.io/f2calv/charts/signalcli \
  --namespace my-namespace --create-namespace \
  --set-string 'signalcli.persistentVolumeClaims[0].name=signalcli-pvc' \
  --set-string 'signalcli.persistentVolumeClaims[0].accessModes[0]=ReadWriteOnce' \
  --set-string 'signalcli.persistentVolumeClaims[0].storage=512Mi' \
  --set-string 'signalcli.persistentVolumeClaims[0].storageClassName=longhorn'
```

Or set the same values via Argo CD manifest:

```yaml
signalcli:
  persistentVolumeClaims:
    - name: signalcli-pvc
      accessModes:
        - ReadWriteOnce
      storage: 512Mi
      storageClassName: longhorn
```

To grow the volume later, raise `storage` in your values and let the release reconcile. Never edit
the PVC directly: under a GitOps controller with self-heal the change is reverted, and because a
PVC cannot shrink the resource is then stuck permanently out of sync. Growing at all requires a
StorageClass with `allowVolumeExpansion: true`.

### Ephemeral installs

The volume can be removed entirely for a throwaway evaluation, at the cost of re-registering the
account after every restart. There is no `persistence.enabled` toggle, because the storage values
are consumed by a subchart and Helm resolves subchart values before templating, so the chart cannot
conditionally remove them. Clear all three lists instead:

```bash
helm upgrade --install signalcli oci://ghcr.io/f2calv/charts/signalcli \
  --namespace my-namespace --create-namespace \
  --set-json 'signalcli.volumes=[]' \
  --set-json 'signalcli.volumeMounts=[]' \
  --set-json 'signalcli.persistentVolumeClaims=[]'
```

Or set the same values via an Argo CD manifest:

```yaml
signalcli:
  volumes: []
  volumeMounts: []
  persistentVolumeClaims: []
```

### Moving an account between volumes

The registration is ordinary files, so it can be copied into a new claim. Scale down first: the
message database is a live SQLite file and copying it from under a running JVM can capture a torn
write.

```bash
kubectl scale --namespace my-namespace deployment/signalcli --replicas=0
kubectl cp --namespace my-namespace <helper-pod>:/home/.local/share/signal-cli ./signal-cli-backup
```

The account JSON holds the device's private keys. Treat the copy as a credential: it is enough to
impersonate the linked device. Note also that Signal's double ratchet advances with every message,
so restoring a *stale* copy over an account that has kept running leaves the session desynchronised
and messages undecryptable — restore the most recent state, or re-link the device instead.

## Related Projects

- [bbernhard/signal-cli-rest-api](https://github.com/bbernhard/signal-cli-rest-api)
- [CasCap.Api.SignalCli](https://github.com/f2calv/CasCap.Api.SignalCli) provides typed .NET clients
  for the REST and JSON-RPC APIs.
- [signalizr](https://github.com/f2calv/signalizr) provides a controlled Signal gateway for
  applications that should not own an account connection directly.
