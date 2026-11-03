# Upgrading deployments

Applies to: operators of orchestrator, node, Elsa, InfluxDB connector and UI containers.
Current values for variables: [env-vars.md](../contracts/env-vars.md); ports, users and volumes: [images.md](../contracts/images.md).

## Procedure

1. Read the sections below, and the `CHANGELOG.md` of each repository whose image you update.
2. Back up: `deploy/backup.sh` (or `backup.ps1`) saves every volume, InfluxDB and `.env`
   ([backup-and-restore.md](backup-and-restore.md)). Without the compose install, back up the
   orchestrator's `/app/StoredObjects`, `/app/MatterCredentials` and `/app/Backups`, Elsa's
   `/app/Data` and the node's `/app/Data`.
3. Pull and restart the containers. With the compose install, `git pull` in `deploy/` updates the
   pinned image tags; then run `docker compose up -d --wait`. Update a **Node image and its plugin package together**:
   plugins run inside the node's `RIoT2.Core` version. Update the node image first, then install
   the plugin zip; since Node 1.14.0 the node refuses a plugin built for a newer Core.
4. Check `GET /health` on each service (or `docker compose ps`), and the node list in the UI.

## System health page (Orchestrator 1.20.0, UI 1.10.0)

No port, user, volume or variable changes ([I46](../increments/phase-3-4.md#i46-system-health-page-m)). Update the orchestrator first: the UI's new
*System* page needs it, while the rest of UI 1.10.0 works with older orchestrators. The page's
presence history starts when the orchestrator starts.

## Core 2.0

Orchestrator 1.19.0, Elsa 1.10.0, InfluxDB connector 1.11.0, Prometheus exporter 1.1.0, and Node,
Devices and RasPi.Devices 2.0.0 ([I45](../increments/phase-3-4.md#i45-core-20-remove-compatibility-layers-m)). No port, user, volume or
variable changes, and the wire format, the stored files and the configuration hashes are the same.

- **Update the node and its plugins together.** Node 2.0.0 refuses a plugin built on Core 1.x and
  keeps the plugins it has, and the 2.0.0 plugins need Node 2.0.0. Point each node configuration's
  plugin package at the 2.0.0 zip of RIoT2.Net.Devices or RIoT2.Net.RasPi.Devices when you update
  the node image. A plugin from elsewhere must be rebuilt on Core 2.0.0.
- Device configurations load unchanged: every parameter keeps its key. Devices that now validate
  their parameters start in the error state, with the missing key in the state message, when a
  required value is missing: credentials (APsystems, ENTSO-E, water meter, Netatmo, Hue), the Hue
  bridge, the eufy service host and the Z-Wave `nodeId`.
- Scripts that send the `json-naming-policy` header now get camelCase like everyone else.
- Plugin authors: see the Core CHANGELOG. `DeviceBase`'s constructor is `[Obsolete]`, Core no longer
  reads Newtonsoft attributes or ships Newtonsoft.Json, and `IDevicePlugin.Devices` is gone.

## Mobile quick hardening (RIoT2.Mobile 1.1.0)

Install the new APK over the old one; no server changes
([I44](../increments/phase-3-4.md#i44-mobile-quick-hardening-s)). On first use the app moves the
beacon key from plain settings to encrypted storage. If the beacon stops after the update, enter
the key again in Settings. A restored phone backup never carries the key.

## Matter completion (Orchestrator 1.18.0)

No port, user, volume, variable or JSON changes ([I43](../increments/phase-3-4.md#i43-matter-completion-m)); only Matter users notice it.

- A bridged endpoint now always keeps its endpoint id. If the bridge earlier gave a device another
  device's id (a device added while another was out of the configuration, then a restart), the
  controller app may still show the wrong name or room for it: remove and re-add that device in the app.
- Bindings written by a Matter controller now open connections to their targets (through mDNS), so the
  orchestrator may contact devices it only listed before.

## Wiegand peripheral (M5Core2 and M5Dial 0.6.0)

Flash over OTA as before; no setting changes
([I42](../increments/phase-3-4.md#i42-wiegand-peripheral-s)). The boards offer a new *Wiegand Reader* peripheral template; nothing changes until a
configuration adds it.

## Async-first plugins (Node 1.15.0, Devices 1.7.0, RasPi.Devices 1.6.0)

No port, user, volume, variable, JSON or behaviour changes
([I41](../increments/phase-3-4.md#i41-async-first-plugins-and-the-plugin-template-m)). **Update the node to 1.15.0 before installing
Devices 1.7.0 or RasPi.Devices 1.6.0**, which are built on Core 1.23.0; an older node refuses them
and keeps its plugins. Older plugins keep working on Node 1.15.0.

Plugin authors: on Core 1.23.0 the synchronous members of `AsyncDeviceBase` throw instead of
blocking. Remove `public void ExecuteCommand` shims (CS0114), or mark them `override`, and call
devices in tests through their async members or `DeviceCalls`. New plugins start with
`dotnet new riot2-plugin` ([plugin-authoring.md](plugin-authoring.md)).

## Connectors in the UI and the Prometheus exporter (Orchestrator 1.17.0, UI 1.9.0, connector 1.10.0, exporter 1.0.0)

No port, user or volume changes for the existing services ([I39](../increments/phase-3-4.md#i39-connectors-in-the-ui-and-a-prometheus-exporter-m)).

- Update the orchestrator and the UI together: the UI's connector list reads
  `GET /api/v2/connectors`; against an older orchestrator it stays empty.
- The InfluxDB connector announces itself as a connector (`nodeType` 4) named `InfluxDB`
  (`RIOT2_CONNECTOR_NAME` changes it). Compose sets `RIOT2_CONNECTOR_URL`; without compose, set it
  to a URL the orchestrator reaches, or the UI shows the connector without its health.
- `compose.observability.yml` adds the `prometheus-exporter` service (image
  `riot2-prometheus-exporter`), a Prometheus job `riot2-values` and the **RIoT2 values** dashboard.
  `git pull` in `deploy/` brings them; new optional `.env` settings:
  `RIOT2_PROMETHEUS_MAX_AGE_MINUTES` and `RIOT2_PROMETHEUS_EXPORTER_API_KEY`.
- `riot2_nodes_online` gains `type="connector"`.

## Connector spool (connector 1.9.0)

The connector keeps messages on disk while InfluxDB is down ([I38](../increments/phase-3-4.md#i38-connector-spool-m)).
No port or user changes; the line protocol is unchanged.

- New volume: the spool is in `/app/Data/spool`. `git pull` in `deploy/` brings the
  `influxdb-connector-data` volume; without the compose install, mount `/app/Data` (writable by
  UID 1654), or the spool is lost when the container is recreated.
- New variables, all optional: `RIOT2_CONNECTOR_SPOOL` (default `true`),
  `RIOT2_CONNECTOR_SPOOL_MAX_MB` (100) and `RIOT2_CONNECTOR_SPOOL_MAX_AGE_DAYS` (7). Add them to
  `deploy/.env` only to change the defaults.
- Batches InfluxDB refuses (400, 413, 422) are kept in `/app/Data/spool/dead-letter.jsonl`
  instead of dropped.
- `/health` now answers 503 while MQTT is disconnected, and reports InfluxDB and the spool;
  `/healthz` is unchanged. New metrics: `riot2_connector_spool_depth`,
  `riot2_connector_spool_bytes` and `riot2_connector_spool_dropped_total`.

## Connector SDK (connector 1.8.0)

No port, user, volume or variable changes ([I37](../increments/phase-3-4.md#i37-connector-sdk-m)); the
line protocol in InfluxDB is unchanged.

- Writes are batched (up to 100 messages, or after 1 s). A failed write is retried with backoff
  instead of dropped; reports received before the orchestrator's templates are written once
  they arrive.
- Commands (`RIOT2_HANDLE_COMMANDS=true`) are stamped with the time the connector received them.
- `riot2_connector_writes_total` counts messages with `outcome` `written`, `retried`, `rejected`
  or `discarded` (no longer points with `failed`), and `ignored` messages are counted when they
  are written. Update alerts that used `outcome="failed"`.

## Sync and command status (Orchestrator 1.16.0, Elsa 1.9.0, UI 1.8.0)

No port, user, volume, variable or JSON changes
([I36](../increments/phase-3-4.md#i36-sync-and-command-status-in-the-ui-m)). Update the
orchestrator first: UI 1.8.0 needs its `GET /api/v2/nodes/sync` (with an older orchestrator the
Configuration column shows "unknown" and re-apply fails).

- The Configure page shows each node's configuration sync and re-applies it; "delivery queue"
  shows the outbox. Dashboard buttons and switches show whether their command ran.
- The UI sends commands with `POST /api/v2/commands`; `POST /api/command/execute` still works for
  other callers.
- Elsa has "RIoT Command with confirmation"; existing workflows are unchanged.
- Elsa's image carries the patched ASP.NET Core 10.0.14 WebAssembly and SignalR packages.

## Verified plugin updates (Node 1.14.0)

No port, user, volume, variable or JSON changes
([I35](../increments/phase-3-4.md#i35-verified-plugin-updates-m)). The node installs the
configuration's `pluginPackageUrl` safely:

- It reads `<url>.sha256` (every Devices and RasPi.Devices release has it) and installs only a
  package whose hash matches, built for the same Core major and a minor no newer than its own.
  A refused package leaves `/app/Plugins` alone: the node shows `failed` with the reason and its
  devices keep running. It isn't tried again; delete `Data/plugins.rejected.json` in the node
  volume to retry the same package.
- An update is staged in `/app/Plugins.new` and installed at the next start; the previous
  plugins wait in `/app/Plugins.previous`. If the new package doesn't load, the node puts them
  back and exits with code 75 once; the compose `restart: unless-stopped` starts it again. Keep a
  restart policy on nodes that install packages.
- Plugins copied into `./plugins` by hand stay as they are, unless the configuration names
  another package (as before).

## Security seams (Orchestrator 1.15.0, Node 1.13.0, Elsa 1.8.0, connector 1.7.0, UI 1.7.0)

No port, user, volume or JSON changes, and nothing is enforced
([I34](../increments/phase-2.md#i34-security-seams-with-the-mode-fixed-at-off-m)); update in any order.

- New optional variables ([env-vars.md](../contracts/env-vars.md#shared-variables)):
  `RIOT2_SECURITY_MODE` accepts only `off` yet (`audit` or `on` stops the start), `RIOT2_API_KEY`
  is sent to the other services, and `RIOT2_MQTT_TLS`/`RIOT2_MQTT_CA_FILE` connect to a TLS broker.
- The compose UI gets `ORCHESTRATOR_UPSTREAM=http://orchestrator:8080`: the browser calls the API
  through the UI's origin. Without it (`docker run`) the UI calls the orchestrator directly, as before.
- The plugin URL check reports the HTTP error instead of `Error in Web.GetHeaders`.

## Older releases

Upgrading from Orchestrator 1.9.0 to 1.14.x, Node 1.8.0 to 1.12.x (supply chain, nullable reference
types, async device drivers, typed device options, plugin packaging, the Core package split, typed
persistence, System.Text.Json, the UI and orchestrator restructures):
[upgrading-1.9-to-1.14.md](upgrading-1.9-to-1.14.md).

Upgrading from images before Orchestrator 1.9.0, Node 1.8.0 and firmware 0.5.0 (metrics, backup
and restore, consistent logging, firmware command results, desired-state configuration, command
results and API v2, the compose install, firmware OTA rollback, the rule engine's retirement,
durable workflow delivery, the plugin SDK, CI-built releases, .NET 10 and the September 2026
images): [upgrading-older.md](upgrading-older.md).
