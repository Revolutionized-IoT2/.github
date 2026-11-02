# Design 7.4: Operations, as built

Applies to: the compose install, the four .NET services and the UI. What each phase of
[design 7.4](operations.md) delivered, and where it differs from the design. The decisions and
the phase plan are in operations.md.

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

## As built: phase 2 (I20)

Core `1.9.0` with the new package `RIoT2.Core.Hosting`, Orchestrator and Node `1.6.0`, Elsa `1.4.0`
and the InfluxDB connector `1.3.0`, 2026-11-01. Variables: [env-vars.md](../contracts/env-vars.md#shared-variables).

- **Packages.** `LoggingOptions` (`RIOT2_LOG_FORMAT`, `RIOT2_LOG_LEVEL`) and `LogScope` are in
  `RIoT2.Core`, which stays free of Serilog, so device plugins don't get it. `AddRIoT2Logging()` is
  in `RIoT2.Core.Hosting` (net10.0), released from the Core tag like the plugin test kit. Each
  service's options type reads `LoggingOptions` too, so an invalid value is reported with the
  service's other settings; until then the default is used.
- **Pipeline.** Serilog writes to the console and to `Logs/RIoT2.log` (relative to the working
  directory, `/app/Logs` in the images; compose mounts a volume for every service), as text
  (`<time> [INF] <category>: <message> [CorrelationId=…]`) or `RenderedCompactJsonFormatter` JSON,
  with a `Service` property. The file rolls daily and at 50 MB and keeps 14 files. `Microsoft.*`
  and `System.*` start at `Warning`. `RIOT2_LOG_LEVEL` replaces the `Logging` sections of the
  images' `appsettings.json`, which were removed.
- **One logger factory.** The host keeps its own `LoggerFactory`, with Serilog as its provider, so
  providers that tests add still work. The factory `AddRIoT2Logging()` returns is for start-up
  code: its loggers forward to the host's factory once it exists, so the Node's and Orchestrator's
  long-lived loggers share scopes with every `ILogger<T>`.
- **Ids.** `OutboxDispatcher` opens a `CorrelationId` (commands) or `MessageId` (workflow
  triggers) scope around each delivery; `CommandOutbox` scopes the queueing and the result. The
  .NET node's `NodeMqttService` runs each command in a `CorrelationId` scope, which reaches the
  device's log lines, and Elsa's gRPC trigger runs in a `MessageId` scope.
- Tests: RIoT2.Tests `LoggingTests` (options, text and JSON lines, scopes across loggers, levels,
  file, start-up loggers forwarding to the host's providers).

## As built: phase 3 (I21)

Orchestrator `1.7.0` and UI `1.3.0`, 2026-11-01. Use: [backup-and-restore.md](../guides/backup-and-restore.md).

- **API** (`BackupController`, [http-api.md](../contracts/http-api.md#backup-backupcontroller-apiv2)):
  `POST /api/v2/backup`, `POST /api/v2/restore` (zip body), and `GET /api/v2/backups`,
  `GET /api/v2/backups/{name}` and `POST /api/v2/backups/{name}/restore` for the files in
  `Backups/`, which the UI's *Backup* page lists.
- **Archive** (`BackupArchive`): the manifest, then `StoredObjects/<Type>/<Id>.json` byte for byte
  (`FileObjectStore.Export`, read while saves wait) and `MatterCredentials/…`. Reading rejects,
  with every reason, a foreign manifest or newer format, an entry that isn't listed or doesn't
  match its size and SHA-256, an unsafe or unexpected path (so never `outbox.db`), stored objects
  that aren't JSON, and oversized archives. `BackupService` also loads every known type, and
  refuses a Matter credentials directory that isn't a folder of its own.
- **Restore**: saves a `pre-restore` backup, then, inside `IMatterBridgeService.RunStoppedAsync`,
  replaces the stored objects under the `StoredObjectService` lock (`FileObjectStore.ReplaceAll`
  swaps staged type folders in, and puts the old ones back on a failure), mirrors the credentials
  folder and reloads `OrchestratorConfigurationService`. `AnnounceReplaced` then raises the
  stored-object events: nodes get a configuration command, variables are published, Matter
  endpoints refresh and removed nodes lose their retained status.
- **Schedule**: `BackupScheduler` waits for the next `RIOT2_BACKUP_SCHEDULE` time (Quartz
  `CronExpression`, local time zone) and writes `riot2-backup-<UTC time>.zip`; every save deletes
  all but the newest `RIOT2_BACKUP_RETENTION`. Compose sets `0 0 3 * * ?` and mounts the
  `orchestrator-backups` volume.
- **Host scripts** (`deploy/backup.sh`, `.ps1`, `restore.sh`, `.ps1`): one deviation from
  decision 5: instead of `sqlite3 .backup`, the services that write SQLite (orchestrator, Elsa,
  node, Grafana) are stopped while the volumes are archived, which makes plain `tar` copies
  consistent. InfluxDB's volumes are left to `influx backup` and `influx restore --full`; log
  volumes are skipped.
- **Encryption** (`RIOT2_BACKUP_PASSPHRASE`) waits for the security mode
  ([I53](../increments/optional-security.md#i53-signing-and-secrets-at-rest-m)).
- Tests: RIoT2.Tests `BackupTests`; the end-to-end `BackupRestoreTests` (fresh stack, running
  stack and node, undo, changed archive, schedule); `deploy-check.yml` restores through the API
  and runs both script pairs against wiped volumes.

## As built: phase 4 (I22)

Core and `RIoT2.Core.Hosting` `1.10.0`, Orchestrator `1.8.0`, Node `1.7.0`, Elsa `1.5.0`, connector
`1.4.0`, 2026-11-01. Every instrument: [metrics.md](../contracts/metrics.md). Variables:
[env-vars.md](../contracts/env-vars.md#shared-variables).

- **Instruments** use `System.Diagnostics.Metrics` directly, one meter per service
  (`Diagnostics/MeterNames` in Core), plus `RIoT2.Mqtt` in Core's `MqttClient`. The node's
  instruments live in Core (`NodeMetrics`), because Core's `NodeMqttService`, `DeviceServiceBase`
  and `NodeConfigurationStatus` do the work; Core itself has no OpenTelemetry dependency.
- **Export** is `AddRIoT2Telemetry(service, id, meters)` in `RIoT2.Core.Hosting` (OpenTelemetry
  1.20.1): the service's meter, `RIoT2.Mqtt`, ASP.NET Core and runtime metrics over OTLP, with
  `service.name` `riot2-<service>` and the RIoT2 id as `service.instance.id`. It adds nothing unless
  `OTEL_EXPORTER_OTLP_ENDPOINT` is set; `RIOT2_TRACING=true` adds traces (ASP.NET Core without
  `/health`, HTTP and gRPC clients, `RIoT2.*` sources).
- **Observability profile** is `deploy/compose.observability.yml`: the OpenTelemetry Collector
  (contrib `0.164.0`, OTLP in, a Prometheus endpoint out, traces to its log), Prometheus `v3.15.1`
  (15 days) and Grafana with the "RIoT2 system" dashboard (`deploy/grafana/dashboards`). Grafana is
  the same service as in `compose.influx.yml`; each file mounts only its own data source. The
  services read the endpoint from `.env`, so one setting covers the connector and a Raspberry Pi
  node too.
- **Deviations**: `riot2.nodes.out_of_sync` counts online configured nodes, by state (`pending`,
  `failed`). `riot2.workflow.deliveries` also counts `retry` attempts. The connector's spool metrics
  came with the spool (Core 1.21.0, I38); the firmware `diag` gauges wait for the 7.2 firmware
  status, as the I22 scope says. The added `riot2.node.reports.dropped`,
  `riot2.node.devices` with every state at zero, and `riot2.mqtt.dropped` (in Core since 1.3.0)
  are documented with the others.
- `riot2.node.device_restarts` counts running devices stopped by a configuration change. The
  end-to-end reconnect test asserts that it stays at zero across a reconnect and counts the control
  restart.
- Tests: RIoT2.Tests `MetricsTests`, `OrchestratorMetricsTests`, `ConnectorMetricsTests`, and Elsa
  `ElsaMetricsTests` pin every name, tag and value; docs-check's `metrics` rule keeps
  metrics.md, the code and the dashboard's `riot2_*` queries in step. deploy-check starts the
  observability profile and waits for the metrics in Prometheus and the dashboard in Grafana.

## As built: phase 5 (I40)

`.github/workflows/nightly-smoke.yml` and `tools/compose-smoke/`, 2026-11-02 (no product release).

- **Nightly.** At 03:37 UTC (and on demand) the images pinned in `deploy/` start on a clean runner with
  `docker-compose.yml`, `compose.influx.yml`, `compose.observability.yml` and the `node` profile, from
  `.env.example` with random secrets (`tools/compose-smoke/env.sh`, shared with `deploy-check.yml`).
- **Checks** (`tools/compose-smoke/health.py`, standard-library Python with a self-test in the hub's CI):
  every container running and healthy; `/health` of the orchestrator, Elsa and the node; the UI and its
  `/api` proxy; InfluxDB, Prometheus and Grafana; both connectors' own health through
  `GET /api/v2/connectors`; and `up{job="riot2-values"}`. All must pass within 2 minutes of the start;
  the job summary has a table with the time each check took.
- **Reporting.** A failure opens an issue labelled `nightly-smoke` in the hub (or comments on the open
  one) with a link to the run, and uploads the compose logs; the next passing run closes it. Running it
  by hand with `simulate-failure` requires an endpoint that doesn't exist, to test the report.
- **Deviations.** `deploy-check.yml` runs the same `health.py` after its own start, so a change in
  `deploy/` is held to the nightly checks too. The design's "within 2 minutes" is measured from
  `docker compose up` after the images are pulled.
