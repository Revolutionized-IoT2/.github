# Design 7.3: Connector SDK (A6)

Applies to: see below. Status: **proposed, not implemented**. Written for the September 2026
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
   depends on `RIoT2.Core.Contracts` and `RIoT2.Core.Mqtt` ([M1](../plans/m01-split-core-packages.md)). Until M1 lands it references the
   `RIoT2.Core` facade.
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
| 1 | Create the SDK by extracting the generic Influx code. Add `ReceivedUtc` stamping, batching and retry. The Influx connector becomes the first consumer, with identical output ([M7](../plans/m07-contract-integration-tests.md) golden messages compare the resulting line protocol before and after). |
| 2 | Disk spool, dead-letter file, shutdown drain, health and metrics. This fixes the Influx part of [backlog item 2](../backlog/open-issues.md). |
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
