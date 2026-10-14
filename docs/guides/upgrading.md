# Upgrading deployments

Applies to: operators of orchestrator, node, Elsa, InfluxDB connector and UI containers.
Current values for ports, users and variables: [env-vars.md](../contracts/env-vars.md).

## Procedure

1. Read the sections below, and the `CHANGELOG.md` of each repository whose image you update.
2. Back up the orchestrator's `/app/StoredObjects` and `/app/MatterCredentials`, Elsa's
   `/app/Data` and the node's `/app/Data`.
3. Pull and restart the containers. Update a **Node image and its plugin package together**:
   plugins run inside the node's `RIoT2.Core` version. Update the node image first, then install
   the plugin zip.
4. Check `GET /health` on each service, and the node list in the UI.

## Automation: internal rule engine retired

Elsa 3 is the only automation engine
([ADR 0003](../adr/0003-elsa-sole-automation-engine.md)).

- Rules stored by older versions (`StoredObjects/Rule`) are no longer executed, and they are not
  migrated. Rebuild them as Elsa workflows.
- Reports reach Elsa automatically once it is online; no switch is needed.
- Without Elsa, state tracking continues but no automation runs.

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
