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

## .NET 10 images and plugins (late 2026)

.NET 8 and .NET 9 reach end of support on 10 November 2026. From the releases built on Core `1.0.1`,
every .NET image runs on .NET 10 and the device plugins target `net10.0`.

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
