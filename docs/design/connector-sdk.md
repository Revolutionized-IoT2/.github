# Design 7.3: Connector SDK (A6)

Applies to: see below. Status: **accepted 2026-10-12 ([ADR 0009](../adr/0009-connector-sdk.md)); phases 1–2 implemented (Core `1.20.0`/`1.21.0`, connector `1.8.0`/`1.9.0`, [I37](../increments/phase-3-4.md#i37-connector-sdk-m), [I38](../increments/phase-3-4.md#i38-connector-spool-m), see [As built](#as-built-phase-1-i37)); phases 3–4 not implemented**. Written for the September 2026
platform review; "current behaviour" describes the code at that time. Verify before starting.
Design IDs `7.1`–`7.5` are stable. Architecture context: [target.md](../architecture/target.md).

**Current state (verified in code).** `RIoT2.Connector.InfluxDB` is the only connector. About
three quarters of its code is generic:

- **MQTT lifecycle** (`ConnectorMqttService`): announces itself on `riot2/node/{id}/online` with
  `NodeType` left at `Unknown` and a hard-coded name `InfluxDBConnector`, re-announces when the
  orchestrator comes online, receives `ConfigurationCommand` and subscribes to
  `riot2/node/+/report` and, optionally, `riot2/node/+/command`.
- **Template catalog** (`TemplateService`): loads report, command and variable templates from
  three orchestrator endpoints.
- **Queue** (`InfluxDBService`): an in-memory bounded channel of 1000 items, batches of 100, and no
  retry. A failed batch is logged and dropped, and a batch in flight at shutdown is lost.

Only the point mapping (`MqttMessageHandlerService`, `EntityFlattener`) and the InfluxDB write are
Influx-specific. Commands are stamped with `DateTime.UtcNow` when they are mapped, so a replayed
command would get the wrong time.

## Decisions

1. **Location and target.** `RIoT2.Connector.Sdk` is a package in the RIoT2.Core repository, released
   from the same tag and targeting `net10.0` ([A10](../architecture/target.md#a10-unify-engineering-practices)), because it needs ASP.NET Core hosting. It
   depends on `RIoT2.Core.Contracts` and `RIoT2.Core.Mqtt` (since Core 1.13.0,
   [M1](../plans/m01-split-core-packages.md)).
2. **Spool raw envelopes, not mapped items.** The SDK queues and spools a `ConnectorMessage` and the
   sink maps it at write time. Spooling therefore works for any sink without a serializer per sink,
   and a replay after an outage uses the original timestamps.

   ```csharp
   public sealed record ConnectorMessage(
       ConnectorMessageKind Kind,   // Report | Command
       string NodeId,               // from the topic
       string Json,                 // original payload
       DateTimeOffset ReceivedUtc); // stamped on receipt, used for commands

   public interface IConnectorSink
   {
       // Throw TransientSinkException to retry the batch, SinkRejectedException to dead-letter it.
       Task WriteAsync(IReadOnlyList<ConnectorMessage> batch, ITemplateCatalog templates, CancellationToken ct);
       Task<bool> CheckHealthAsync(CancellationToken ct) => Task.FromResult(true);
   }

   // Program.cs of a connector
   builder.AddRIoT2Connector<InfluxSink>(options => options.Name = "InfluxDB");
   ```

3. **Optional disk spool.**
   - Messages go to memory first. When the sink fails or the in-memory queue is more than 80 %
     full, they are appended to JSON-lines segment files under `/app/Data/spool`, with a checkpoint
     file, and replayed in order once the sink is healthy.
   - Limits are 100 MB and 7 days by default. When a limit is reached, the oldest segment is
     dropped and counted in a metric.
   - The spool is on by default for Influx, because gaps in history are permanent. It can be
     switched off (`RIOT2_CONNECTOR_SPOOL=false`) for connectors where only live data matters.
   - JSON-lines files are used instead of SQLite because the workload is append-only and
     sequential.
4. **Retries and dead letters.**
   - Batches are flushed at `BatchSize` (default 100) or `BatchInterval` (default 1 s).
   - A transient failure is retried with backoff (1 s … 60 s) while new messages go to the spool.
   - A permanent rejection writes the batch to `/app/Data/spool/dead-letter.jsonl` with the error,
     so one bad message doesn't block the queue.
   - Shutdown drains memory to the spool within a 10 s timeout, so nothing in flight is lost.
5. **Identity.** Add `NodeType.Connector = 4` (additive). The orchestrator only acts on `Device` and
   `Workflow`, so older orchestrators ignore connectors as they do today. The UI can list
   connectors separately. The name and id come from configuration.
6. **Writing back into RIoT2.** For bidirectional connectors (Home Assistant, feature list), the
   SDK provides an `IRiot2CommandClient` that calls `POST /api/v2/commands` ([7.1](reliable-delivery.md)). Connectors
   never publish command topics directly, so the outbox, TTL and results apply to them too.
7. **Built-in cross-cutting features.**
   - [M4](../plans/m04-typed-configuration.md) options (`RIOT2_MQTT_*`, `RIOT2_CONNECTOR_ID`, `RIOT2_HANDLE_COMMANDS`, `RIOT2_CONNECTOR_SPOOL*`).
   - `/health`, combining MQTT connection, sink health and spool usage.
   - Metrics under `riot2.connector.*` ([7.4](operations.md)).
   - The API key header when security mode is on ([7.5](security-mode.md)).

## Phases

| Phase | Content |
|---|---|
| 1 | **Done (I37).** Create the SDK by extracting the generic Influx code. Add `ReceivedUtc` stamping, batching and retry. The Influx connector becomes the first consumer, with identical output: RIoT2.Tests `GoldenInfluxTests` compares the line protocol for every golden message with [Golden/influx-line-protocol.txt](https://github.com/Revolutionized-IoT2/RIoT2.Tests/blob/main/Golden/influx-line-protocol.txt) (I05). |
| 2 | **Done (I38).** Disk spool, dead-letter file, shutdown drain, health and metrics. This fixes the Influx part of [backlog item 2](../backlog/open-issues.md). |
| 3 | `NodeType.Connector` and a UI connector list. |
| 4 | Second connector to validate the abstraction: a Prometheus exporter (pull-based, so it exercises the sink without the spool), followed by Home Assistant MQTT discovery with `IRiot2CommandClient`. |

## Tests

- Sink failures are retried, then spooled.
- The spool replays in order and resumes after a restart.
- A full spool drops the oldest segment and counts it.
- A permanent rejection is dead-lettered and the queue keeps moving.
- Shutdown loses nothing.
- Influx output is byte-identical to today's for the golden messages, except that commands now use
  their receive time.

## Open points (defaults chosen)

- Spool limits (100 MB / 7 days).
- Whether commands should be exported by default. They stay off, as today
  (`RIOT2_HANDLE_COMMANDS=false`).

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
