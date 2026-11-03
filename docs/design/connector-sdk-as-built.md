# Design 7.3 as built: connector SDK

Applies to: RIoT2.Core (`RIoT2.Connector.Sdk`), the connectors, Orchestrator and UI. How the phases of
[design 7.3](connector-sdk.md) were implemented, and where the code differs from the design.
The contracts are in [http-api-services.md](../contracts/http-api-services.md),
[mqtt-topics.md](../contracts/mqtt-topics.md) and [env-vars.md](../contracts/env-vars.md).

## As built: phase 1 (I37)

Core `1.20.0` (the package `RIoT2.Connector.Sdk`, in `RIoT2.Core/Connector/`) and connector `1.8.0`,
2026-11-02. The connector's `Program.cs` is
`builder.AddRIoT2Connector<InfluxSink, InfluxConnectorOptions>(...)` and `app.MapRIoT2Connector()`.

- **What the SDK has.** `ConnectorOptions` (`RIOT2_CONNECTOR_ID`, `RIOT2_HANDLE_COMMANDS`, MQTT,
  logging, telemetry, security; the connector reads its own settings from the same reader, so
  one error lists every problem), `ConnectorMqttService`, `TemplateCatalog`, `ConnectorPipeline`,
  `ConnectorMetrics` (the `riot2.connector.*` instruments moved here) and the host extensions.
  No environment variable changed.
- **Mapping moved to write time.** The MQTT side only checks that a report or command is readable
  (`invalid` otherwise) and queues the raw envelope with `ReceivedUtc`. The sink maps it when the
  batch is written; a message it skips is counted `ignored` then. A sink must map each message on
  its own: an exception from one message would otherwise drop its whole batch.
- **Batching and retry.** Batches of up to 100, waiting up to 1 s to fill (the old writer sent what
  was there at once). `TransientSinkException` retries the same batch, 1 s doubling to 60 s,
  while new messages wait in the queue (1000; beyond that they are refused and counted
  `failed`). `SinkRejectedException` or any other exception drops the batch (`rejected`), until
  the dead-letter file of phase 2. Stopping ends the waits, writes what is queued for up to 10 s
  and discards the rest (`discarded`); a transient failure while stopping discards its batch.
- **The Influx sink** treats 400, 413 and 422 as rejected and everything else (network, timeouts,
  401, 403, 404, 429, 5xx) as transient, so a wrong token or a missing bucket loses nothing once
  fixed. Until the templates are loaded a batch is transient too: reports received before the
  orchestrator's configuration command are written once it arrives (they used to be dropped).
- **Output.** The golden line protocol is unchanged; commands carry their receive time
  (`GoldenInfluxTests` also checks the timestamp now). `riot2.connector.writes` counts messages
  by `written`, `retried`, `rejected` and `discarded` instead of points by `written`, `failed`
  and `discarded` ([metrics.md](../contracts/metrics.md)).
- Not yet: the spool, the dead-letter file, a `/health` that checks the sink (still a constant
  `ok`), `NodeType.Connector` and `IRiot2CommandClient` (phases 2–4).
- Tests: RIoT2.Tests `ConnectorSdkTests` (batching, retry, rejection, shutdown, the MQTT side,
  settings), `InfluxSinkTests` (the request, status mapping, waiting for templates),
  `InfluxReliabilityTests` (catalog, mapping), `ConnectorMetricsTests` and `GoldenInfluxTests`.

## As built: phase 2 (I38)

Core `1.21.0` and connector `1.9.0`, 2026-11-02. `ConnectorSpool` (internal) does the files;
`ConnectorPipeline` decides where a message goes.

- **Memory first, then disk.** Messages go to the in-memory queue. The first transient failure
  moves the failed batch and everything waiting in memory into the spool, ahead of anything
  already there, and from then on new messages are appended to the spool until it has been
  written; they also go there once the memory queue is 80 % full. The worker always empties memory
  before it reads the spool, so the order is kept. Once the spool is written it is deleted, and
  new messages use memory again. Spooled batches are retried in place with the same backoff.
- **Files** in `/app/Data/spool` (`ConnectorSpoolOptions.Path`; the image creates the folder, and
  compose mounts the `influxdb-connector-data` volume at `/app/Data`):
  - Segment files `<number>.jsonl`, one `ConnectorMessage` per line. Each is closed at 4 MB (or a
    tenth of the limit) or after an hour, and a restart starts a new one. Messages that belong
    ahead of the spool get new lower numbers; those files are written under temporary names and
    renamed once all are on disk, so a failure adds nothing. A segment is forgotten only once its
    file is deleted.
  - `checkpoint.json` (a segment and a byte offset), written atomically after each batch. The
    delivery is at least once: a batch interrupted by stopping is written again at the next start.
  - `dead-letter.jsonl`: one line per rejected message with `rejectedUtc` and `error`; moved to
    `dead-letter.1.jsonl` at 10 MB.
  - Appends are flushed to the operating system on every message; segments written at a failure
    or a stop are flushed to disk.
- **Limits.** `RIOT2_CONNECTOR_SPOOL_MAX_MB` (100) drops the oldest segment, and
  `RIOT2_CONNECTOR_SPOOL_MAX_AGE_DAYS` (7) drops a closed segment by its last write.
  An unreadable line (or one torn by a crash) is skipped. All three count in
  `riot2.connector.spool_dropped` (`size`, `age`, `unreadable`).
- **Stopping.** The write in flight gets up to `DrainTimeout` (10 s); what waits in memory, and an
  unfinished batch, are spooled at once instead of written.
- **Health.** `/health` returns `ConnectorHealthReport`: `unhealthy` (503) while MQTT is
  disconnected, `degraded` while the sink's `CheckHealthAsync` fails (InfluxDB's `/ping`, 5 s) or
  messages wait in the spool. `/healthz` stays a constant `ok`. New gauges:
  `riot2.connector.spool_depth` and `riot2.connector.spool_bytes`.
- **Off switch.** `RIOT2_CONNECTOR_SPOOL=false` keeps the phase 1 behaviour exactly. Options built
  in code (`new ConnectorOptions()`) have the spool off; `ConnectorOptions.Read` turns it on.
- **Deviations.** The memory queue's high-water mark spools new messages rather than the queue's
  content. A disk error while spooling refuses the message (`failed`) and logs it; a failed move
  to the spool falls back to retrying from memory.
- Tests: RIoT2.Tests `ConnectorSpoolTests` (failure and replay in order, restart, checkpoint, stop,
  dead letters, the size and age limits, the high-water mark, unreadable lines, settings, health)
  and `InfluxSinkTests.HealthPingsInflux`.

## As built: phases 3 and 4 (I39)

Core `1.22.0`, Orchestrator `1.17.0`, UI `1.9.0`, InfluxDB connector `1.10.0` and the new repository
`RIoT2.Connector.Prometheus` `1.0.0`, 2026-11-02.

- **Identity.** `NodeType.Connector = 4` (golden file `node-online-connector`). The SDK's presence carries
  the type, the name (`RIOT2_CONNECTOR_NAME`, else the connector's default: `InfluxDB`, `Prometheus`),
  `nodeBaseUrl` from the optional `RIOT2_CONNECTOR_URL`, and a manifest: the connector's assembly name and
  version, and the SDK's version as `coreVersion`. Presence stays unretained, with the MQTT client's offline
  last will; connectors announce themselves again when the orchestrator comes online.
- **Orchestrator.** `GET /api/v2/connectors` lists online connectors and reads each one's `/health`
  (8 s, longer than the connector's 5 s for its target, in parallel; the body also with 503), so the browser needs no access to the connectors.
  `riot2.nodes.online` counts them as `type="connector"`. Nothing else changes: connectors still get the
  configuration command, and no device templates are asked from them.
- **UI.** The Nodes page lists connectors under the nodes: name, version (SDK version in a tooltip),
  health (`ok`, `degraded`, `unhealthy`, `unreachable`, or `online` without a URL, with the reasons) and
  spooled messages, polled every 10 s. The node editor offers only device nodes' ids.
- **Shared mapping.** `EntityFlattener` moved from the InfluxDB connector into the SDK.
- **Prometheus exporter.** A sink that keeps the latest value of every report (and command, with
  `RIOT2_HANDLE_COMMANDS`) field and serves `/metrics` (`riot2_value`, `riot2_value_timestamp_seconds`,
  [metrics.md](../contracts/metrics.md#prometheus-exporter)). No spool and no batch delay; an older report
  doesn't replace a newer one; values not sent again within `RIOT2_PROMETHEUS_MAX_AGE_MINUTES` (60) leave.
  `compose.observability.yml` runs it, Prometheus scrapes it (job `riot2-values`), and the dashboard
  "RIoT2 values" shows the values. docs-check now also checks the exporter's families.
- **Deviation.** The design's pull-based exporter still receives through the SDK's queue (memory only),
  which proved the sink abstraction fits a target that keeps state instead of writing.
- Tests: RIoT2.Tests `ConnectorListTests`, `PrometheusExporterTests`, `GoldenPrometheusTests`
  (`Golden/prometheus-exposition.txt`), the presence and settings cases in `ConnectorSdkTests`, and the
  golden presence; UI `tests/connectors.test.cjs`.

## As built: phase 4, Home Assistant (I47)

Core `2.1.0` and the new repository `RIoT2.Connector.HomeAssistant` `1.0.0`, 2026-11-03.

- **`IRiot2CommandClient` (SDK).** `SendAsync(commandId, value, CommandSendOptions?)` posts to the
  orchestrator's `POST /api/v2/commands` (time-to-live, optional `wait`) and returns the
  `CommandDeliveryInfo`; `400` and `404` throw `CommandRejectedException`. The orchestrator's URL comes
  from the configuration command (`OrchestratorEndpoint`), so the connector needs no extra setting; the
  HTTP client `riot2-commands` sends `RIOT2_API_KEY` like every other outbound call.
- **`IConnectorTemplateObserver` (SDK).** Called after every loaded template set; one failing observer
  is logged and doesn't stop the others. `ConnectorTemplate` now also carries the device and node id,
  the address, the value type and the parameters.
- **Discovery.** Every report and command template is one Home Assistant entity in one device per
  connector: boolean reports `binary_sensor`, numbers `sensor` (unit and precision from the template's
  `unit` and `precision` parameters), entities `sensor` with JSON attributes, text arrays `sensor` with the count as the state, text `sensor`;
  boolean commands `switch` (its state from the boolean report of the same device and address, else
  optimistic), numbers `number`, other commands `text`. Config messages are retained; ones that are no
  longer in the templates are deleted with an empty retained message, also after a restart (the
  connector reads its old configs back). Discovery is published again on Home Assistant's birth message.
  Ids are `riot2_<connector id>_<id>`, where `<id>` is the template id, made topic-safe with a short hash
  when it has other characters than letters, digits, `_` and `-`.
- **States and commands.** The sink publishes each report's value as the entity's retained state (no
  spool, no batch delay; it is transient while the templates or the broker are missing). A command
  from Home Assistant on `riot2/ha/<id>/set` goes to `IRiot2CommandClient` with
  `RIOT2_HA_COMMAND_TTL_SECONDS` (60) and is never published on the RIoT2 command topic, so the
  orchestrator's delivery tracking and authorization stay in charge.
- **Deviation.** The design left the second broker open: the connector uses the RIoT2 broker unless
  `RIOT2_HA_MQTT_IP` names Home Assistant's own. Core's `MqttEventArgs` has no retain flag, so the
  cleanup treats every non-empty config under the connector's own id as seen.
- Tests: RIoT2.Tests `HomeAssistantTests` (mapping, topics, sanitized ids, command values, stale
  configs, the sink and the bridge), and the SDK's command client and observer cases.
