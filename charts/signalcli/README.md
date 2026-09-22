# signalcli

Deploys the [bbernhard/signal-cli-rest-api](https://github.com/bbernhard/signal-cli-rest-api)
container, a REST and JSON-RPC wrapper around [signal-cli](https://github.com/AsamK/signal-cli).

The upstream project ships no Helm chart. This one supplies the parts that are easy to get wrong:
a volume for account state, probes that match what the image actually exposes, resources sized for
a JVM, and schema validation of the environment variables that change its behaviour.

## Install

```bash
helm install signalcli oci://ghcr.io/f2calv/charts/signalcli --version <version>
```

The chart depends on [`workload`](../workload/README.md), pulled from `oci://ghcr.io/f2calv/charts`.
Everything under `signalCli` is passed to that subchart, so its keys are the workload chart's keys.

## Registering an account

**Deploying the chart is the easy half.** The container is useless until a Signal account is
registered or linked to it, and that state must land on the persistent volume.

1. Port-forward the service:

   ```bash
   kubectl port-forward svc/signalcli 8080:80
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
| `signalCli.image.tag` | `0.100` | Pinned rather than empty — see below |
| `signalCli.envVars.MODE` | `json-rpc` | Validated. Also decides the receive endpoint's shape |
| `signalCli.envVars.LOG_LEVEL` | `info` | Validated |
| `signalCli.persistentVolumeClaims` | 512Mi `ReadWriteOnce` | Set to `[]` for an ephemeral install |

Environment variables keep their upstream names verbatim, so each traces directly back to the
bbernhard documentation. The map stays **open**: a variable added by a newer image release can be
set immediately, without waiting for a chart release. The variables the chart knows about are
validated, so a bad value fails the install rather than the pod:

```text
at '/signalCli/envVars/MODE': value must be one of 'normal', 'native', 'json-rpc', 'json-rpc-native'
```

### MODE changes the receive contract

`json-rpc` and `json-rpc-native` make `/v1/receive/{number}` a **WebSocket**. The other modes leave
it a plain `GET`. A consumer written against one will not work against the other, so choose
deliberately rather than by performance alone.

### Why the image tag is pinned

The workload subchart falls back to *its own* `appVersion` when `image.tag` is empty, which would
resolve to the workload chart's version and pull an image that does not exist. Keep
`signalCli.image.tag` in step with this chart's `appVersion`.

## Deliberate defaults

- **`replicaCount` is capped at 1 by the schema.** signal-cli registers one device against one
  account and keeps state on one volume. More than one replica is invalid, not merely unwise.
- **No liveness probe.** A JVM that is slow or busy is not a JVM that should be killed, and a
  restart drops the registered session and forces every consumer to reconnect.
- **Readiness on `/v1/about`**, which answers only once the JVM has loaded account state — the
  moment it can actually serve traffic. The image exposes no `/healthz`.

## Receiving messages

The wrapper broadcasts each inbound message to every connected receive socket over an unbuffered
channel with a non-blocking send. A consumer that is not parked inside a receive at that instant
**misses the message**, with no retry and no error — only a debug line in the wrapper's log.

If more than one process needs inbound messages, have a single owner drain the stream into a
buffered queue and fan out from there, rather than each consumer holding its own socket.
