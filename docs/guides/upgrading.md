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

## Supply chain (Orchestrator 1.14.2, Node 1.12.1, Elsa 1.7.2, connector 1.6.3, UI 1.6.1)

No port, user, volume, variable, JSON or behaviour changes; update in any order
([I33](../increments/phase-2.md#i33-supply-chain-s)). The images are rebuilt on digest-pinned
base images and carry an SBOM and provenance, so a tag names an image index; `docker pull` and
compose handle it as before.

## Nullable reference types (Node 1.12.0, Orchestrator 1.14.1, connector 1.6.2, Devices 1.6.0, RasPi.Devices 1.5.0)

No port, user, volume, variable, JSON or behaviour changes
([I32](../increments/phase-2.md#i32-nullable-reference-types-m)). **Update the node to 1.12.0
before installing the Devices 1.6.0 or RasPi.Devices 1.5.0 plugin**, which are built on Core
1.17.0. Older plugins keep working. Plugin authors: Core 1.17.0 is nullable-annotated;
override `Refresh`/`RefreshAsync` with `ReportTemplate?`.

## Async device drivers (Node 1.11.1, Devices 1.5.0, RasPi.Devices 1.4.0)

No port, user, volume, variable or JSON changes; update in any order
([I31](../increments/phase-2.md#i31-async-cleanup-part-2-and-threading-analyzers-m)). Devices 1.5.0
needs Node 1.11.0 or newer, RasPi.Devices 1.4.0 Node 1.10.0. The network devices no longer block
the node while they wait, and a configuration change cancels their requests. Node 1.11.1 puts a
device whose request times out into the error state with the reason, where it used to show
stopped. The Netatmo Weather and Hue templates list what the device read at its last start or
refresh. The RasPi Z-Wave devices open the stick when they start, and close it again when a start
fails.

## Typed device options (Node 1.11.0, Orchestrator 1.14.0, UI 1.6.0, Devices 1.4.0)

No port, user, volume or variable changes; stored configurations and their hashes are unchanged.
**Update the node to 1.11.0 before installing the Devices 1.4.0 plugin**, which is built on Core
1.16.0 ([I30](../increments/phase-2.md#i30-typed-device-options-m)). The node now matches
parameter keys case-insensitively. AzureRelay, EasyPLC, FTP, Mqtt and Messaging validate their
parameters at start: a missing required value (Mqtt `serverUrl`, EasyPLC `ipAddress`, all four
AzureRelay keys) or a non-numeric port puts the device into the error state, with the reason in
its status, where it used to fall back silently. EasyPLC's `port` now defaults to 10001 and FTP's
`ftpPort` to 21. The UI shows typed fields and hides secrets for devices of an online node; update
it with the orchestrator (the order doesn't matter).

## Plugin packaging (Devices and RasPi.Devices 1.3.1)

No image changes. The 1.3.1 plugin zips hold the same files as 1.3.0 and need Node 1.10.0 or
newer, like 1.3.0; their build now packs them ([I29](../increments/phase-2.md#i29-plugin-packaging-s)).
Plugin authors: reference `RIoT2.Core.Devices.Build` and set `RIoT2PluginName`.

## Narrow Core references (Orchestrator 1.13.1, Node 1.10.0, Elsa 1.7.1, connector 1.6.1, UI 1.5.0)

Skip Orchestrator 1.13.0, Elsa 1.7.0 and connector 1.6.0: they fail at start (a missing
`Microsoft.Bcl.AsyncInterfaces`). No port, user, volume, variable or JSON changes. Each service references only the Core packages
it uses ([I28](../increments/phase-2.md#i28-narrow-references-and-generated-models-m)). **Update the node to 1.10.0 before installing the
1.3.0 plugins** (RIoT2.Net.Devices, RIoT2.Net.RasPi.Devices): they are built against Core 1.14.0,
and an older node doesn't load them. Installed older plugins keep working on Node 1.10.0.

## Core package split (Orchestrator 1.12.0, Node 1.9.0)

No port, user, volume, variable or JSON changes; update in any order. Installed plugins keep
working; a plugin rebuilt against RIoT2.Core 1.13.0 needs Node 1.9.0.

## Typed persistence (Orchestrator 1.11.0)

No port, user, volume or variable changes. The stored configuration keeps its format, and a return
to 1.10.0 reads it; take a backup first anyway (this release changes the storage code). Emoji are
written unescaped again, as before 1.10.0, so a node whose configuration has one re-applies it once. At its first start the orchestrator moves the retired rule engine's
`StoredObjects/Rule` files to `StoredObjects/.archive/Rule` and logs a warning. The
`json-naming-policy` request header is deprecated: answers carry `Deprecation: true`, and Core 2.0
(I45) removes it. Scripts that send it should use the default camelCase.

## System.Text.Json (Orchestrator 1.10.0, Node 1.8.0, Elsa 1.6.0, connector 1.5.0)

No port, user, volume or variable changes; update in any order. The JSON on MQTT, over HTTP and in
`StoredObjects/` is the same, so configuration hashes don't change and no node re-applies its
configuration. For plugin authors (RIoT2.Core 1.11.0): an `object` member read from JSON holds a
`JsonElement` for an object or array instead of a `JObject`, and invalid JSON throws
`System.Text.Json.JsonException`. Existing plugin builds keep working.

## UI restructure (UI 1.4.0)

No port, user, volume or variable changes; works with Orchestrator 1.7.0 or later. The UI now
announces itself on every MQTT connection and when the orchestrator restarts, so open pages no
longer stay on "Connecting..." after a restart. Its presence is camelCase; every orchestrator reads
it. Menu labels: **Workflows** (was Rules) and **Variables**.

## Orchestrator restructure (Orchestrator 1.9.0)

No port, user, volume, variable or route changes; update in any order. Two template listings gain
fields: `GET /api/nodes/report/templates` has each template's `model` (it was `null`), and
`GET /api/nodes/variable/templates` an empty `address`. The UI ignores both.

## Older releases

Upgrading from images before Orchestrator 1.9.0, Node 1.8.0 and firmware 0.5.0 (metrics, backup
and restore, consistent logging, firmware command results, desired-state configuration, command
results and API v2, the compose install, firmware OTA rollback, the rule engine's retirement,
durable workflow delivery, the plugin SDK, CI-built releases, .NET 10 and the September 2026
images): [upgrading-older.md](upgrading-older.md).
