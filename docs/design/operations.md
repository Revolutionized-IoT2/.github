# Design 7.4: Operations (A9)

Applies to: see below. Status: **accepted 2026-10-12 ([ADR 0012](../adr/0012-operations-first-class.md)); phase 1 done 2026-10-14 (I12, [as built](#as-built-phase-1-i12)), phases 2–5 not implemented**. Written for the September 2026
platform review; "current behaviour" describes the code at that time. Verify before starting.
Design IDs `7.1`–`7.5` are stable. Architecture context: [target.md](../architecture/target.md).

## Current state (verified in code and deployment docs)

- Every service is started with a separate `docker run` command copied from READMEs; there is no
  compose file. (Fixed by phase 1.)
- **Health:** orchestrator, node, Elsa and Influx now expose `/health` (the orchestrator and node
  checks include MQTT), and the UI image has a `wget` health check. The node image has no Docker
  `HEALTHCHECK` yet. (Fixed by phase 1: every image has one.)
- **Logs:**
  - The orchestrator and node use Serilog, writing to the console and to
    `Logs/RIoT2.log` rolled daily with no size limit.
  - Elsa and Influx use plain console logging.
  - All output is human-readable text; none of it is structured.
- There are no metrics.
- **No backup exists. The data to protect is:**
  - Orchestrator `StoredObjects` (node configurations, dashboards and variables) and
    `MatterCredentials`. If the credentials are lost, every Matter device has to be recommissioned.
  - Elsa `Data/elsa.sqlite.db` (workflow definitions).
  - Node `Data/` (Netatmo and Firebase tokens, and since Node 1.5.0 the saved configuration of [7.2](desired-state-configuration.md), `configuration.applied.json`).
  - The Mosquitto password and ACL files.

## Decisions

1. **Compose layout** in this `.github` repository under `deploy/`:
   - `docker-compose.yml`: `mosquitto`, `orchestrator`, `elsa`, `ui`, plus `node` under a `node`
     profile, for a single-host setup.
   - `compose.influx.yml`: InfluxDB, Grafana and the connector.
   - `compose.observability.yml`: OpenTelemetry Collector, Prometheus and Grafana.
   - `compose.matter.yml`: an override putting the orchestrator on `network_mode: host`, which
     mDNS and IPv6 need.
   - `compose.node-raspi.yml`: runs on the Raspberry Pi itself, privileged, with D-Bus mounted.

   Configuration comes from a single `.env` built from a committed `.env.example` with every
   variable documented. Services use named volumes, and `depends_on: condition: service_healthy`
   gives the start order mosquitto → orchestrator → elsa, node and ui. `RIOT2_SECURITY_MODE` is set
   once in `.env` ([7.5](security-mode.md)). Images are pinned to release tags, with a comment on how to pin digests.
2. **Logging.**
   - Serilog in all four .NET services through a shared `AddRIoT2Logging()` extension ([M4](../plans/m04-typed-configuration.md) options).
   - Console output stays human-readable by default; `RIOT2_LOG_FORMAT=json` switches to compact
     JSON (`Serilog.Formatting.Compact`) for log collectors.
   - The file sink keeps `rollingInterval: Day`, adds `fileSizeLimitBytes: 50 MB` and
     `rollOnFileSizeLimit`, and retains 14 files.
   - The message and correlation ids from [7.1](reliable-delivery.md) are added as log scope properties, so one command can
     be followed from UI to device.
3. **Metrics.**
   - Instrument with `System.Diagnostics.Metrics` (one `Meter` per service: `RIoT2.Orchestrator`,
     `RIoT2.Node`, `RIoT2.Elsa`, `RIoT2.Connector`). This is built in, so there is no cost while
     nothing listens.
   - Export over OTLP through the OpenTelemetry SDK only when the standard `OTEL_EXPORTER_OTLP_ENDPOINT`
     is set.
   - The observability profile runs a Collector that exposes a Prometheus scrape endpoint, with
     Prometheus and Grafana and a provisioned "RIoT2 system" dashboard. Grafana is already part of
     the Influx setup, so it is familiar.
   - Traces are opt-in (`RIOT2_TRACING=true`) over the same pipeline. No trace backend is bundled
     by default.
4. **First metrics.**

   | Service | Metrics |
   |---|---|
   | Orchestrator | `riot2.reports.received` (by node), `riot2.reports.unknown_template`, `riot2.workflow.deliveries` (by outcome), `riot2.outbox.pending`, `riot2.outbox.oldest_age_seconds`, `riot2.commands` (by outcome), `riot2.command.latency` (histogram, needs 7.1), `riot2.mqtt.connected`, `riot2.mqtt.reconnects`, `riot2.nodes.online`, `riot2.nodes.out_of_sync` (7.2) |
   | Node | `riot2.node.devices` (by state), `riot2.node.device_restarts` (proves [backlog item 18](../backlog/open-issues.md) is fixed), `riot2.node.commands` (by outcome), `riot2.node.reports.published`, `riot2.node.config_applies` (by result) |
   | Elsa | `riot2.workflow.triggers` (received, duplicate), `riot2.workflow.faults` |
   | Connector | `riot2.connector.messages`, `riot2.connector.writes` (by outcome), `riot2.connector.queue_depth`, `riot2.connector.spool_bytes`, `riot2.connector.spool_dropped` |
   | Firmware | Heap, RSSI and uptime as an optional `diag` object in the 7.2 status message. The orchestrator turns these into `riot2.firmware.*` gauges. |

5. **Backup and restore, at two levels.**
   - **Configuration backup (no downtime):**
     - `POST /api/v2/backup` on the orchestrator returns a zip of `StoredObjects` (without
       `outbox.db`) and `MatterCredentials`, plus a `backup-manifest.json` with versions, date and
       file hashes.
     - `POST /api/v2/restore` validates an uploaded zip, briefly pauses writes, replaces the files
       and reloads the caches.
     - An optional nightly job (`RIOT2_BACKUP_SCHEDULE`, a cron expression evaluated with
       Quartz, which is already a Core dependency) writes to `/app/Backups` and keeps
       `RIOT2_BACKUP_RETENTION=7`.
     - Backup and restore are also available as UI buttons (feature list).
   - **Full system backup (short downtime):**
     - `deploy/backup.sh` and `deploy/backup.ps1` stop Elsa and the orchestrator for a few seconds
       and archive every named volume with `docker run --rm -v <volume>:/data alpine tar`. SQLite
       files are copied with `sqlite3 .backup` or `VACUUM INTO` so the copies are consistent.
     - They then restart the services. `restore.sh` and `restore.ps1` do the reverse.
     - InfluxDB data is excluded; the script calls `influx backup` when the Influx profile is
       active.
   - Backups contain secrets (device parameters, Matter keys, tokens). The docs say so. When
     security mode is on, backups are encrypted with a passphrase (AES-GCM, key derived with
     PBKDF2), set via `RIOT2_BACKUP_PASSPHRASE`.

## Phases

| Phase | Content |
|---|---|
| 1 | Compose files, `.env.example`, a node `HEALTHCHECK`, and a compose quick start in the profile README replacing the individual `docker run` commands. This is a quick win. |
| 2 | Shared logging extension in all services: Serilog everywhere, retention, JSON option, correlation scope. |
| 3 | Configuration backup/restore API, nightly job, host scripts and UI buttons. |
| 4 | Meters in code, OTLP export, observability profile with Grafana dashboard. |
| 5 | Nightly container smoke test ([M7](../plans/m07-contract-integration-tests.md) step 5) using the compose stack. |

## As built: phase 1 (I12)

- **Files** in [deploy/](../../deploy/): `docker-compose.yml`, `compose.influx.yml`,
  `compose.matter.yml`, `compose.node-raspi.yml` and `.env.example`, as decided above. The
  observability file comes with phase 4.
- **Broker:** `eclipse-mosquitto:2.0.22` with `deploy/mosquitto/mosquitto.conf` (persistence,
  1883, WebSocket on 9001, no anonymous access). `mosquitto/start.sh` writes the password file
  for the one account `RIOT2_MQTT_USERNAME` on every start, so `.env` is the only place for it.
  The health check subscribes to `$SYS/broker/version` with that account.
- **Addresses:** services reach the broker as `mosquitto` on the compose network. Every URL that
  is advertised to others is built from `RIOT2_HOST` and the host port, because nodes, browsers
  and ESP32 firmware use it as well. The Matter override moves the orchestrator to the host
  network, where it reaches the broker at `127.0.0.1`.
- **Defaults:** `.env.example` has readable ids (`riot2-orchestrator`, `riot2-elsa`,
  `riot2-node-1`) instead of GUIDs, because ids only need to be unique on the broker. Only
  `RIOT2_HOST`, `RIOT2_MQTT_PASSWORD` and `ELSA_IDENTITY_SIGNING_KEY` must be filled in;
  compose stops with a message naming the missing one.
- **Volumes:** named volumes, except the node's `Plugins/`, which is the host folder
  `deploy/plugins` so that plugin zips can be unzipped into it. The orchestrator's `/app/Data`
  isn't mounted, because it only holds the image manifest. The node image now keeps its manifest
  in `/app/Manifest.json` and copies it into `Data/` on start, so a `Data/` volume doesn't show
  an old version.
- **Images:** UI `1.1.0` (`nginx-unprivileged`, port 8080, S12), Node and Orchestrator `1.3.1`
  (`HEALTHCHECK` on `/health`; the arm64 node image installs `wget` for it). Third-party images:
  `influxdb:2.9.1` (set up on first start from `.env`) and `grafana/grafana:13.2.4` (with a
  provisioned InfluxDB data source).
- **Checks:** `.github/workflows/deploy-check.yml` validates every compose combination and starts the stack on a clean
  runner from `.env.example` (once with the node, once with InfluxDB). It waits for every service to be healthy, then checks
  that Elsa and the node register with the orchestrator, that the node reports the pinned
  version, that the UI's bundle contains `RIOT2_HOST`, and that Grafana's data source works.
  docs-check's `deploy` rule keeps `.env.example` in step with the compose files, and its `env`
  rule requires every compose variable in [env-vars.md](../contracts/env-vars.md#compose-install-deploy).

## Tests

- `docker compose config` validation in CI.
- Compose smoke test: all `/health` endpoints report healthy within 2 minutes.
- A backup → wipe → restore round trip in the M7 harness brings back identical `GET /api/nodes`
  and dashboard output.
- Unit tests for the backup manifest validation, rejecting corrupted or foreign zips.
- Metric names are asserted in unit tests, so the dashboards don't break silently.

## Open points (defaults chosen)

- Metrics stay off unless an OTLP endpoint is configured.
- Backups are kept for 7 days.
- Compose lives in this `.github` repository. If it grows, it can move to a dedicated
  `RIoT2.Deploy` repository.
