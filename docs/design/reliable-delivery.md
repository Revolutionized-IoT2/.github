# Design 7.1: Reliable delivery (A3, with A5)

Applies to: see below. Status: **proposed, not implemented**. Written for the September 2026
platform review; "current behaviour" describes the code at that time. Verify before starting.
Design IDs `7.1`–`7.5` are stable. Architecture context: [target.md](../architecture/target.md).

## Current behaviour (verified in code)

| Path | What happens today | Consequence |
|---|---|---|
| Node report → Elsa | `OrchestratorMqttService` puts a gRPC `TriggerRequest{id,data}` into an in-memory channel (capacity 1000). A delivery that fails is logged and dropped ("not retried automatically"). When no workflow node is online the report is dropped with a warning. The queue is discarded on shutdown. | Automation silently misses events during Elsa restarts, upgrades and network blips. |
| Command (UI/Elsa → device) | `POST /api/command/execute` publishes to `riot2/node/{id}/command` and sets the command state immediately (`SetState(command)`), then returns `200`. The node runs it asynchronously; failures, and rejections once more than 64 commands are pending, only appear in the node log. | The UI/Elsa can't tell whether anything happened, and the stored "state" of a command may be wrong. |
| Offline node | .NET clients connect with a clean session, so the broker doesn't queue messages for an offline node. The orchestrator's managed client queues outgoing messages only in memory, and only while the orchestrator itself is disconnected. | Commands to a node that is offline or restarting are lost. |
| Delivery level | `Core/Utils/MqttClient` publishes at QoS 2, but subscribes with `MqttTopicFilterBuilder` defaults, which means **QoS 0**. The broker delivers at the lower of the two levels, so every .NET subscriber effectively receives at QoS 0. `PubSubClient` (firmware) subscribes at QoS 0 and can only publish at QoS 0. | Any message can be silently lost when a connection drops. QoS 2 publishing costs a four-way handshake and buys nothing. |
| Firmware | Views update the display on a command but don't publish a report back. | Lost commands to firmware leave no trace. |
| Late subscribers | The UI loads current state over REST (`/api/dashboard/reports`, `/api/nodes/{type}/{id}/state`), and Elsa's `RIoTData` activity does too. | No gap here, so the retained state snapshot topic considered earlier is not needed. |

## Decisions

1. **Scope.** The outbox covers orchestrator → Elsa (workflow triggers) and orchestrator → node
   (commands). Node → orchestrator reports stay fire-and-forget: they are periodic or repeated by
   nature, and the orchestrator keeps the last value.
2. **Store.** One SQLite file, `/app/StoredObjects/outbox.db`, on the volume that already exists,
   accessed through `Microsoft.Data.Sqlite` with plain SQL (no EF Core). It has one table:

   ```sql
   CREATE TABLE outbox (
     id TEXT PRIMARY KEY,            -- message id (GUID), also the idempotency key
     kind TEXT NOT NULL,             -- 'workflow' | 'command'
     target TEXT NOT NULL,           -- node id, or 'workflow'
     payload TEXT NOT NULL,          -- serialized TriggerRequest / Command
     created_utc INTEGER NOT NULL,
     expires_utc INTEGER NOT NULL,
     next_attempt_utc INTEGER NOT NULL,
     attempts INTEGER NOT NULL DEFAULT 0,
     status TEXT NOT NULL,           -- pending | sent | done | failed | expired
     result TEXT, last_error TEXT);
   CREATE INDEX outbox_due ON outbox(status, next_attempt_utc);
   ```

   Rows in a final state are removed after 24 hours by a cleanup timer.
3. **Semantics.** At-least-once delivery with an idempotency key; receivers deduplicate.
   Deliveries are FIFO per target (one dispatcher loop per target), so commands to one node keep
   their order.
4. **Time-to-live instead of unlimited retry.** Stale automation is worse than none: a light that
   turns on 20 minutes late is a bug. Defaults are 300 s for workflow triggers and 30 s for
   commands. They are configurable through [M4](../plans/m04-typed-configuration.md) options (`RIOT2_OUTBOX_WORKFLOW_TTL`,
   `RIOT2_OUTBOX_COMMAND_TTL`), and a request can override the command TTL (below). Retry backoff
   is 1 s, 2 s, 4 s … capped at 30 s. When the TTL passes, the row becomes `expired` and a
   warning is logged.
5. **No workflow node online.** Keep the trigger as `pending` and deliver it when Elsa announces
   itself, subject to the TTL. This replaces today's drop.
6. **QoS 1 end to end, clean sessions kept.**
   - QoS is set by [M10](../plans/m10-mqtt-client-robustness.md): QoS 1 for publishing and subscribing everywhere. Duplicates are handled by
     the idempotency keys above and the configuration hash in [7.2](desired-state-configuration.md). Firmware subscribes at QoS 1,
     which `PubSubClient` supports.
   - Clean sessions stay. Persistent MQTT sessions would let the broker queue commands, but MQTT
     3.1.1 has no message expiry and gives no status, so the outbox remains the single place for
     retry and expiry.
7. **The command result says "executed", not "physically confirmed".** "Executed" means the
   device's `ExecuteCommand`/`ExecuteCommandAsync` returned without an exception. Physical
   confirmation comes, as today, from the device's next report.

## Contract changes (all additive)

| Item | Change |
|---|---|
| `Command` | Optional `correlationId` (string). Old nodes and firmware ignore unknown fields (ArduinoJson and the .NET deserializers both do). |
| New `CommandResult` model | `{ "correlationId": "…", "commandId": "…", "status": "executed" \| "failed" \| "rejected" \| "unknownCommand" \| "duplicate", "error": "…", "timeStamp": 1790000000 }` |
| New topic | `riot2/node/{id}/command/result` (`MqttTopic.CommandResult`). The node publishes and the orchestrator subscribes to `riot2/node/+/command/result`. Nodes subscribe to their exact command topic, so this one doesn't overlap. |
| `NodeOnlineMessage` | Optional `capabilities` string array, e.g. `["command-result/1","desired-state/1"]` (the second is from 7.2). The orchestrator waits for results only from nodes that advertise `command-result/1`. Commands to other nodes are marked `sent` and treated as done, which is today's behaviour. |
| gRPC `TriggerRequest` | Add `string message_id = 3;` (wire-compatible). Elsa deduplicates on it: it keeps the ids seen in the last 10 minutes and answers `success=true` without re-running the workflow. |
| REST | `POST /api/command/execute` is unchanged: it still returns `200` once the command is queued. New `POST /api/v2/commands` accepts `{ "id", "value", "ttlSeconds"?, "wait"? }` and returns `{ "correlationId", "status" }`. With `"wait": true` it blocks until a final status or the TTL. New `GET /api/v2/commands/{correlationId}` and `GET /api/v2/outbox/summary` (counts per status, oldest pending, last errors). |
| Health | `/health` reports `Degraded` when the oldest pending row is older than half its TTL or more than 500 rows are pending. |

## Node and firmware behaviour

- The .NET `NodeMqttService` passes `correlationId` through `ICommandService`. After execution it
  publishes a `CommandResult`. Today's silent rejection when more than 64 commands are pending
  becomes `rejected`. It keeps a deduplication cache of the last 256 correlation ids (10 minutes)
  and answers repeats with `duplicate` without running the command again.
- Firmware (`RIoT2.Ard.Shared/MqttConnection`) gets the same logic: a result after
  `onCommand`, a ring buffer of the last 16 ids, command subscription at QoS 1, and the capability
  in its online message.
- Command state: for nodes with `command-result/1`, the orchestrator sets the command state when
  the result is `executed`. For legacy nodes it keeps setting it on send.

## Implementation phases

| Phase | Repos | Content |
|---|---|---|
| 1 | Orchestrator, Elsa | `IAutomationProvider` ([A5](../architecture/target.md#a5-keep-automation-behind-a-provider-interface)) wrapping `WorkflowTriggerClient`; SQLite outbox and dispatcher for workflow triggers; `message_id` and Elsa deduplication; outbox summary endpoint and health. No node changes. |
| 2 | Core, Orchestrator, Node | `correlationId`, `CommandResult`, topic and capability in Core (one Core release shared with 7.2 phase 1); orchestrator command outbox and v2 endpoints; node result publishing and deduplication. |
| 3 | Ard.Shared, both firmwares | Result publishing, deduplication, QoS 1 command subscription, capability flag. |
| 4 | Elsa, UI | "Command with confirmation" Elsa activity using `wait:true` (feature list); command status indicator in the UI; outbox view on the health page. |

**Tests** (on the [M7](../plans/m07-contract-integration-tests.md) in-process harness, plus unit tests for the store and backoff):

- A trigger is redelivered after the workflow stub fails twice.
- A trigger created while no workflow node is online is delivered when one appears.
- A trigger past its TTL expires.
- A duplicate `message_id` doesn't re-run the workflow.
- A command to an offline node expires with status `expired`.
- A command to a capable node ends as `executed`; a throwing device ends as `failed`.
- A repeated `correlationId` returns `duplicate`.
- Pending rows survive an orchestrator restart.

## Open points (defaults chosen; revisit if they don't fit)

- The TTL defaults (300 s / 30 s).
- Whether `wait:true` should be the default for Elsa.
