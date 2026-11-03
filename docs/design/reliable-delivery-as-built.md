# Design 7.1 as built: reliable delivery

Applies to: Orchestrator, Elsa, Node, the firmware and the UI. How the phases of
[design 7.1](reliable-delivery.md) were implemented, and where the code differs from the design.
The contracts are in [http-api.md](../contracts/http-api.md), [mqtt-topics.md](../contracts/mqtt-topics.md)
and [env-vars.md](../contracts/env-vars.md).

## As built: phase 1 (I11)

Orchestrator `1.3.0` and Elsa `1.3.0`, 2026-10-14. The contracts are in [http-api.md](../contracts/http-api.md)
(`/api/v2/outbox/summary`, `/health`, `message_id`) and [env-vars.md](../contracts/env-vars.md) (`RIOT2_OUTBOX_WORKFLOW_TTL`).

- `IAutomationProvider` has `ReportReceivedAsync` and `NodeOnlineChanged`. A variable change needs
  no event of its own: the orchestrator publishes it as a report, which comes back through its
  report subscription. `ElsaAutomationProvider` stores the trigger before it returns, and runs the
  dispatcher for target `workflow` as a hosted service.
- `OutboxStore` uses one connection without pooling, WAL and `synchronous=NORMAL`, and
  `PRAGMA user_version = 1` for later migrations. Two columns were added to the table above:
  `subject` and `updated_utc`.
- Outcomes: `success=true` → `done`. `success=false` or `InvalidArgument` → `failed`, logged as an
  error and never retried. Any other error or a timeout (five seconds) → retried after the backoff.
  Waiting for a workflow node is not an attempt. When a workflow node announces itself, the backoff
  of waiting triggers is reset, because Elsa sets no last will and a crashed Elsa looks online.
- A call's gRPC deadline is five seconds or the trigger's expiry, whichever comes first, and Elsa
  doesn't start a request that arrives after its deadline. So no trigger runs after its TTL.
- Expiries are logged as one warning a minute at most, with the count and the last trigger.
- Elsa's `TriggerDeduplicator` keeps ids in memory for ten minutes. A duplicate that arrives during
  the first run waits for it; a failed run is forgotten, so its redelivery runs.
- Tests: the trigger tests above run in RIoT2.Tests (`ReliableDeliveryTests` on the harness,
  `OutboxStoreTests`, `WorkflowRoutingTests`). The duplicate `message_id` test runs in RIoT2.Elsa
  against the real gRPC service, because the harness uses a workflow stub; the harness shows that
  a redelivery carries the same id.

## As built: phase 2 (I15)

Core `1.7.0`, Node `1.4.0` and Orchestrator `1.4.0`, 2026-10-14 (the types came with Core `1.6.0`
in I14). The contracts are in [http-api.md](../contracts/http-api.md#commands-commandscontroller-apiv2commands)
and [mqtt-topics.md](../contracts/mqtt-topics.md) (`CommandResult`, `correlationId`, `capabilities`).

- `CommandOutbox` stores every command (from `POST /api/command/execute`, `POST /api/v2/commands`,
  Elsa and the Matter bridge) as an outbox row of kind `command` whose target is the node id, and
  runs one `OutboxDispatcher` per node. The row id is the `correlationId`.
- A node without `command-result/1` is sent the command once; the row is final with the result
  `sent`, and the command state is set then, as before. A node with it must answer within 5 s,
  or the command is sent again with the same id after the usual backoff.
- Outcomes: `executed` and `duplicate` are `done`; `failed` and `unknownCommand` are `failed` and
  not retried; `rejected` is retried. A result that arrives after its attempt stopped waiting still
  completes the row, even an expired one, because the node got the command in time.
- The node (`NodeMqttService`, Core) keeps the last 256 correlation ids for 10 minutes
  (`CorrelationCache`). It answers `rejected`, and forgets the id, when a device isn't running yet
  (`DeviceNotReadyException`) or the command belongs to a configuration that is still being applied:
  a node that comes online receives its waiting commands together with its configuration. A command
  cancelled by a node shutdown gets no answer and runs again after the restart; one cancelled because
  its device was stopped or reconfigured is `failed`. A redelivery never runs twice: while the first
  delivery runs it gets no answer of its own, afterwards `duplicate` (executed; the orchestrator sets
  the state) or the first delivery's `failed` or `unknownCommand` again.
- `RIOT2_OUTBOX_COMMAND_TTL` (default 30 s) and `ttlSeconds` per request; `wait` defaults to `false`.
- Backlog item 7 came along: the six state-changing `GET` routes have `/api/v2` `POST`/`DELETE`
  routes, and the old routes are deprecated aliases that log once and send a `Deprecation` header.
- Tests: the 7.1 command tests above, in RIoT2.Tests (`CommandOutboxTests`; `CommandDeliveryTests`
  end to end with the real Node), and the node side in RIoT2.Net.Node (`NodeCommandResultTests`).

## As built: phase 3 (I19)

Firmware `0.5.0` (M5Core2, M5Dial), 2026-11-01, in `RIoT2.Ard.Shared` `NodeRuntime`: a ring of 16
ids. An unknown id is `rejected` until a configuration is applied and while a fetch is pending. A
correlated `system.ota` is answered before the restart; its id survives it in NVS (`duplicate`).

## As built: phase 4 (I36)

Elsa `1.9.0` and UI `1.8.0` (with Orchestrator `1.16.0`), 2026-11-02.

- **Elsa.** "RIoT Command with confirmation" (`RIoTConfirmedCommand`): the same command and value
  expression as RIoT Output, sent with `POST /api/v2/commands` and `"wait": true`, a timeout of 1 to
  50 seconds (default 30; the orchestrator client gives up after 60) as `ttlSeconds`. It continues
  on `Done` for `executed`, `duplicate` and `sent` (a node without results), on `Failed` for
  `failed`, `unknownCommand` and `expired`, and sets `Status` and `Error`. An unknown command id
  (`404`) is an incident. RIoT Output stays fire-and-forget.
- **UI commands.** Dashboard controls send through `POST /api/v2/commands` (no longer
  `POST /api/command/execute`) and poll `GET /api/v2/commands/{correlationId}` every 500 ms until
  the delivery is final, at most until it expires. Buttons and switches show a spinner while it is
  pending, a check for three seconds when it ran (or was `sent`), and an error icon with the reason
  until the next command; a failure also reaches the snackbar. A newer command for the same id
  takes over.
- **Outbox view.** The summary is a "delivery queue" dialog (since I46 also on the UI's System page)
  on the Configure page: counts per status, the oldest waiting message and the last ten errors.
- Tests: Elsa `ConfirmedCommandTests` (request, every status's outcome, timeout limit), UI
  `sync-status.test.cjs` (status looks, a delivery followed to `failed`, the outbox).
