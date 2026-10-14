# Upgrading deployments

Applies to: operators of orchestrator, node, Elsa, InfluxDB connector and UI containers.
Current values for ports, users and variables: [env-vars.md](../contracts/env-vars.md).

## Procedure

1. Read the sections below, and the `CHANGELOG.md` of each repository whose image you update.
2. Back up the orchestrator's `/app/StoredObjects` and `/app/MatterCredentials`, Elsa's
   `/app/Data` and the node's `/app/Data`.
3. Pull and restart the containers. With the compose install, `git pull` in `deploy/` updates the
   pinned image tags; then run `docker compose up -d --wait`. Update a **Node image and its plugin package together**:
   plugins run inside the node's `RIoT2.Core` version. Update the node image first, then install
   the plugin zip.
4. Check `GET /health` on each service (or `docker compose ps`), and the node list in the UI.

## Desired-state configuration (Node and Orchestrator 1.5.0)

No port, user, volume or variable changes. Update in any order.

- The node's `/app/Data` volume now also holds `configuration.applied.json`, the configuration it
  last applied. A node that starts while the orchestrator is down runs it. Keep the volume (the
  compose file does); without it the node waits for the orchestrator, as before.
- Reconnects and orchestrator restarts no longer make a Node 1.5.0 download its configuration or
  check its plugin package: it already runs that hash. Saving a node's configuration in the UI
  still applies it at once, and restarts only the devices that changed.
- `GET /api/nodes` reports `syncState`, `desiredRevision`, `appliedRevision` and `lastError` per
  node. A failed configuration download is logged by the orchestrator and kept as `failed` until
  the next save or reconnect; the node keeps running its previous configuration.
- Node presence is retained on the broker, like the firmware's. After the update the orchestrator
  sees a restarted node's last state at once. A node whose configuration is deleted has its
  retained status cleared; its retained presence stays until the node goes offline.
- The first configuration that the 1.5.0 orchestrator sends carries hashes; a Node 1.5.0 restarts
  no device for it.
- An older node keeps working: it fetches on every command as before and shows as `legacy`.

## Command results and API v2 (Node and Orchestrator 1.4.0, UI 1.2.0)

No port, user or volume changes. New optional variable: `RIOT2_OUTBOX_COMMAND_TTL` (seconds,
default 30).

- **Update the Orchestrator before the UI.** UI 1.2.0 deletes nodes and variables and drives the
  Matter bridge through the new `/api/v2` routes, which an older orchestrator doesn't have. The old
  `GET` routes keep working for older UIs, as deprecated aliases that log a warning once.
- Nodes and the orchestrator can be updated in any order. A Node 1.4.0 answers commands with a
  result; an older node, or firmware, is simply sent each command once, as before.
- Commands are no longer lost while a node is offline or restarting: they wait in the
  orchestrator's outbox (`StoredObjects/outbox.db`) for up to `RIOT2_OUTBOX_COMMAND_TTL` and are
  then dropped as `expired`. A command that arrives late is usually worse than none; raise the
  time-to-live if your automation prefers late to never.
- `POST /api/command/execute` still returns 200 once the command is queued. `POST /api/v2/commands`
  returns its delivery status, and with `"wait": true` waits for the final one.
- The command state shown in the UI is set when a Node 1.4.0 reports `executed`, not when the
  command is sent.
- `/health` can report `Degraded` when commands wait for an offline node for more than half their
  time-to-live.

## Firmware OTA rollback (M5Core2 and M5Dial 0.2.0)

No settings change; the provisioned Wi-Fi, MQTT and node id stay.

- From 0.2.0, a new image rolls back to the previous one unless it fetches its configuration from
  the orchestrator within 3 minutes. Keep the orchestrator reachable while you update, and don't
  restart the device during those minutes: a restart before that point rolls back too.
- A `system.ota` command sent while an image is still on trial is refused; send it again after the
  log says `marked valid`.
- The update *to* 0.2.0 is already protected: the trial runs in the new image. Still, update one
  board first.
- The templates a board serves to the orchestrator now carry `type` as a number, as the
  orchestrator expects; nothing to do.

## Compose install, UI on port 8080 (UI 1.1.0, Node and Orchestrator 1.3.1)

[deploy/](../../deploy/) has a compose file for the whole stack
([getting-started.md](getting-started.md)).

- **UI 1.1.0 listens on port 8080 instead of 80** and runs nginx as UID 101
  (`nginx-unprivileged`). Change `-p 80:80` to `-p 80:8080`; nothing else changes. The image's
  health check now probes port 8080.
- Node and orchestrator 1.3.1 add a Docker `HEALTHCHECK` on `/health`. No port, user, volume or
  variable changes. A node without a broker connection now shows as `unhealthy`.
- The node's version in the UI comes from the image again when `/app/Data` is mounted: the node
  copies its manifest into `Data/` on every start. Don't mount the orchestrator's `/app/Data`.

To move an installation from `docker run` to compose:

1. Copy `.env.example` to `.env`. Set `RIOT2_ORCHESTRATOR_ID`, `RIOT2_WORKFLOW_ID` and
   `RIOT2_NODE_ID` to your existing ids: nodes and the stored configuration refer to them. Set
   `RIOT2_MQTT_USERNAME` and `RIOT2_MQTT_PASSWORD` to your existing broker account, so ESP32 nodes
   and other clients keep working: the compose broker has only this one account.
2. Keep your data directories by mounting them over the named volumes in a
   `docker-compose.override.yml` next to `docker-compose.yml` (git ignores it). Compose loads it
   automatically when you give no `-f` option:

   ```yaml
   services:
     orchestrator:
       volumes:
         - /srv/riot2/orchestrator/StoredObjects:/app/StoredObjects
         - /srv/riot2/orchestrator/Logs:/app/Logs
     elsa:
       volumes:
         - /srv/riot2/elsa/Data:/app/Data
     node:
       volumes:
         - /srv/riot2/node/Data:/app/Data
         - /srv/riot2/node/Logs:/app/Logs
         - /srv/riot2/node/Plugins:/app/Plugins
   ```

3. Stop and remove the old containers (`docker rm -f mosquitto riot2-orchestrator riot2-elsa
   riot2-ui riot2-node`), then run `docker compose --profile node up -d --wait`.

## Automation: internal rule engine retired

Elsa 3 is the only automation engine
([ADR 0003](../adr/0003-elsa-sole-automation-engine.md)).

- Rules stored by older versions (`StoredObjects/Rule`) are no longer executed, and they are not
  migrated. Rebuild them as Elsa workflows.
- Reports reach Elsa automatically once it is online; no switch is needed.
- Without Elsa, state tracking continues but no automation runs. Since Orchestrator 1.3.0 the
  workflow triggers wait in the outbox and expire, so `/health` reports `Degraded` while reports
  arrive and no Elsa takes them.

## Durable workflow delivery (Elsa and Orchestrator 1.3.0)

No port, user or volume changes ([design 7.1](../design/reliable-delivery.md)).

- **Update Elsa to 1.3.0 before the orchestrator.** The orchestrator now retries a trigger whose
  answer was lost, with the same `message_id`; Elsa 1.3.0 runs it once. An older Elsa works, but
  may run a retried trigger twice.
- The orchestrator creates `/app/StoredObjects/outbox.db` (SQLite, plus `-wal` and `-shm` files
  while it runs). Keep `/app/StoredObjects` on a volume, as before, and include `outbox.db` in
  full-system backups. Back up while the orchestrator is stopped, or copy all three files.
- Triggers are no longer dropped: they wait while Elsa is offline, are retried after failures, and
  survive an orchestrator restart. A trigger older than `RIOT2_OUTBOX_WORKFLOW_TTL` (optional,
  default 300 s) expires and never runs, because late automation is worse than none.
- `/health` can now report `Degraded` (still HTTP 200), when triggers wait too long. Look at
  `GET /api/v2/outbox/summary` for the reason.

## Plugin SDK (Node 1.3.0, Devices and RasPi.Devices 1.2.0)

No port, user, volume or environment variable changes.

- **Update the node to 1.3.0 before installing the 1.2.0 plugins.** They derive from Core 1.5.0's
  `PluginBase`, which an older node doesn't have, so they fail to load there. Older plugins keep
  loading into the new node.
- The UI now shows the parameters of `AzureRelay`, `EasyPLC`, `FTP`, `Mqtt` and the RasPi
  `RFIDReader` (`interruptPin`). Saved configurations keep working unchanged.
- Netatmo tokens are stored per Netatmo app: `Data/netatmoAuth-<clientId>.json`. The existing
  `Data/netatmoAuth.json` stays with the account that uses it first and gets its client id
  written into it, so nobody has to log in again. Back up the node's `/app/Data` first, as always.
  A second Netatmo account now works with its own client id.

## Devices restart only when their configuration changes (Node and Orchestrator 1.0.2)

No port, user, volume or environment variable changes. Update the orchestrator and the node in
any order; the 1.0.1 plugins keep working.

- A node restarts only the devices whose configuration changed. Reconnects, orchestrator restarts
  and saves of other devices leave running devices alone. To force a device restart, restart the
  node or change the device's configuration.
- A device that isn't running (for example after a start failure) is still retried on every
  configuration message.
- After the orchestrator stops or loses its broker connection, the retained
  `riot2/orchestrator/online` says `{"isOnline":false}` instead of a stale `true`. Tools that read
  that topic must check `isOnline`.

## Releases built by CI (October 2026)

From orchestrator `1.0.1`, Elsa `1.0.2`, InfluxDB connector `1.0.1`, node `1.0.1` and the
plugins `1.0.1`, every release is built and tested by the shared CI
([guides/ci.md](ci.md)). No port, user, volume or environment variable changes.

- Update the node image first, then the plugin zips, as before.
- Each plugin zip has a `<zip>.sha256` sidecar on its GitHub release, and `PluginManifest.json`
  has a `coreVersion` field. The node doesn't check either yet.
- RasPi.Devices now has a release zip. Its repository is private, so download the zip and host it
  where the node can reach it before you set it as the plugin package URL.
- Building an image yourself now needs the feed token as a BuildKit secret:
  `docker build --secret id=nuget_token,env=NUGET_AUTH_TOKEN .`. The `NUGET_AUTH_TOKEN` build
  argument is gone.

## .NET 10 images and plugins (late 2026)

.NET 8 and .NET 9 reach end of support on 10 November 2026. From the releases built on Core `1.0.1`,
every .NET image runs on .NET 10 and the device plugins target `net10.0`. The first such versions
are orchestrator `1.0.0`, Elsa `1.0.1`, InfluxDB connector `1.0.0`, node `1.0.0`, the Devices and
RasPi.Devices plugins `1.0.0`, and UI `1.0.1`.

- **Update the node image before you install the new plugin zip.** A `net10.0` plugin can't
  load into an older `net9.0` node. An older plugin still loads into the new node, so updating
  the node first is always safe.
- The ARM64 node image now uses Ubuntu 24.04 (`aspnet:10.0-noble-arm64v8`) instead of Debian 12.
  Port 80 and root are unchanged.
- No port, user, volume or environment variable changes.

## September 2026 images (breaking deployment changes)

| Image | Change | Action |
|---|---|---|
| orchestrator | Listens on **8080** and runs as non-root UID **1654** | Map `-p 80:8080` (or set `ASPNETCORE_HTTP_PORTS`). `sudo chown -R 1654:1654` the host directories mounted at `/app/StoredObjects`, `/app/Logs` and `/app/MatterCredentials`. With `--network host`, the non-root process can't bind ports below 1024. |
| orchestrator, node, elsa, influxdb | Required environment variables have no defaults; startup fails with a clear log if they are missing or invalid | Set them explicitly (see [env-vars.md](../contracts/env-vars.md)). |
| elsa | Web on **8080**, gRPC still on **5003**, non-root, `ELSA_IDENTITY_SIGNING_KEY` required in Production | Generate a key with `openssl rand -base64 48`, `chown` `/app/Data`, and point `RIOT2_WORKFLOW_URL` at the mapped web port. |
| influxdb | Listens on **8080**, non-root | Update the port mapping. |
| ui | No default MQTT values. Env values are rendered again on every container start (previously only on the first start). | Set the `VITE_MQTT_*` variables. |
| node | Still port 80 and root (GPIO, D-Bus and serial need privileges) | Only the environment variable requirement changes. |

Health endpoints: orchestrator/node/elsa/influx expose `GET /health` (elsa and influx also keep
`/healthz`). The UI image has a `wget` health check on `/`.
