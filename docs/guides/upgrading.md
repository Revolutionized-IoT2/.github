# Upgrading deployments

Applies to: operators of orchestrator, node, Elsa, InfluxDB connector and UI containers.
Current values for ports, users and variables: [env-vars.md](../contracts/env-vars.md).

## Procedure

1. Read the sections below, and the `CHANGELOG.md` of each repository whose image you update.
2. Back up: `deploy/backup.sh` (or `backup.ps1`) saves every volume, InfluxDB and `.env`
   ([backup-and-restore.md](backup-and-restore.md)). Without the compose install, back up the
   orchestrator's `/app/StoredObjects`, `/app/MatterCredentials` and `/app/Backups`, Elsa's
   `/app/Data` and the node's `/app/Data`.
3. Pull and restart the containers. With the compose install, `git pull` in `deploy/` updates the
   pinned image tags; then run `docker compose up -d --wait`. Update a **Node image and its plugin package together**:
   plugins run inside the node's `RIoT2.Core` version. Update the node image first, then install
   the plugin zip.
4. Check `GET /health` on each service (or `docker compose ps`), and the node list in the UI.

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

## Metrics (Orchestrator 1.8.0, Node 1.7.0, Elsa 1.5.0, connector 1.4.0)

No port, user or volume changes, and nothing is exported until you set it up. Update in any order;
plugins built for Core 1.9 keep working with Node 1.7.0.

- New optional variables: `OTEL_EXPORTER_OTLP_ENDPOINT` (the metrics collector),
  `OTEL_METRIC_EXPORT_INTERVAL` and `RIOT2_TRACING`; `git pull` in `deploy/` passes them to every
  service. `RIOT2_TRACING` accepts only `true` or `false`.
- For dashboards, add `compose.observability.yml` and set
  `OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317` in `.env`
  ([deployment.md](deployment.md#metrics-prometheus-and-grafana)). With `compose.influx.yml`, Grafana
  now mounts only `grafana/datasources/influxdb.yml` instead of the whole folder.
- Metric names: [metrics.md](../contracts/metrics.md).

## Backup and restore (Orchestrator 1.7.0, UI 1.3.0)

No port or user changes. Update the orchestrator first: the UI's new *Backup* page needs it.

- The orchestrator writes configuration backups to `/app/Backups`. `git pull` in `deploy/` brings
  the `orchestrator-backups` volume and a nightly schedule at 03:00 (`RIOT2_BACKUP_SCHEDULE`,
  keeping `RIOT2_BACKUP_RETENTION=7`). To turn it off, add `RIOT2_BACKUP_SCHEDULE=` to `.env`.
  Without compose, mount a volume at `/app/Backups` and set the variable; unset means off.
- `deploy/backup.sh`, `restore.sh`, `backup.ps1` and `restore.ps1` back up and restore the whole
  install ([backup-and-restore.md](backup-and-restore.md)).

## Consistent logging (Orchestrator and Node 1.6.0, Elsa 1.4.0, connector 1.3.0)

No port or user changes. Update in any order.

- Every .NET service now logs the same way, to the console and to `/app/Logs/RIoT2.log`. The line
  format changed: `2026-11-01 10:00:00.123 +02:00 [INF] <category>: <message>`, plus
  `[CorrelationId=…]` or `[MessageId=…]` while a command or workflow trigger is delivered, so one
  command can be followed from the orchestrator to the device. Update log filters that parsed the
  old `dd.MM.yyyy` lines.
- New optional variables: `RIOT2_LOG_FORMAT=json` for log collectors, and `RIOT2_LOG_LEVEL`
  (default `Information`). An invalid value stops the service with the usual configuration
  message. `Logging__LogLevel__*` settings no longer apply.
- Log files roll daily and at 50 MB, and 14 are kept (before: daily, without limits). Elsa and the
  connector write files now too; the compose files mount `elsa-logs` and
  `influxdb-connector-logs` at their `/app/Logs`, which `git pull` in `deploy/` brings.

## Firmware command results and desired state (M5Core2 and M5Dial 0.5.0)

Flash the firmware over OTA as before; no settings change. With Orchestrator 1.5.0 or later the
boards then report command results and their configuration status instead of showing as `legacy`,
and a reconnect no longer downloads their configuration again. With an older orchestrator they
behave as 0.4.0 did.

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

## Older releases

Upgrading from images before Node and Orchestrator 1.4.0 (the compose install, firmware OTA
rollback, the rule engine's retirement, durable workflow delivery, the plugin SDK, CI-built
releases, .NET 10 and the September 2026 images): [upgrading-older.md](upgrading-older.md).
