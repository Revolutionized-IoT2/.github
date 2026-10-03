# 0003. Elsa 3 is the only automation engine

- Status: Accepted
- Date: 2026-10-03 (records an existing decision)
- Applies to: RIoT2.Core, RIoT2.Net.Orchestrator, RIoT2.Elsa, RIoT2.UI

## Context

RIoT2 used to have an internal rule engine in Core and the orchestrator (rules, a function catalog,
and NCalc expressions). Elsa 3 provides visual workflow authoring (Elsa Studio), persistence and a
much richer activity model.

## Decision

- Elsa 3 (`RIoT2.Elsa`) is the only workflow and automation engine.
- The internal rule engine, its function catalog, its models and the NCalc dependency are removed
  and must not be reintroduced.
- The orchestrator forwards reports to the online workflow node over gRPC (`riot_trigger.proto`).
- Workflows read values over REST (`RIoTData`) and send commands back through the orchestrator
  (`RIoTOutput`, `POST /api/command/execute`).
- If no workflow node is online, state tracking continues and automation is unavailable.
- Old stored rules are not executed and are not migrated automatically.

## Consequences

- Removing the rule engine was a breaking `RIoT2.Core` API change.
- Automation availability depends on the Elsa container. Delivery reliability is addressed by the
  planned outbox ([design 7.1](../design/reliable-delivery.md)).
- The planned `IAutomationProvider` interface ([A5](../architecture/target.md#a5-keep-automation-behind-a-provider-interface)) keeps the orchestrator
  independent of any one engine without bringing back a second engine.

## Alternatives considered

Keeping both engines. Rejected: two engines meant two sets of semantics, plus duplicated UI and
storage.
