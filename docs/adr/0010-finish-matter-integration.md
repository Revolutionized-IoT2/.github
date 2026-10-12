# 0010. Finish the Matter integration inside the orchestrator (A7)

- Status: Accepted
- Date: 2026-10-12
- Applies to: RIoT2.Net.Orchestrator, RIoT2.Matter

## Context

The Matter bridge already runs inside the orchestrator: `MatterBridgeService` is a hosted service,
its state is stored through `MatterConfigurationStore`, and RIoT2 templates map to bridged
endpoints. Outbound bindings, endpoint id stability and the size of `MatterBridgeService` are still
open. See proposal [A7](../architecture/target.md#a7-finish-the-matter-integration).

## Decision

- Matter stays hosted in the orchestrator process. It doesn't become a separate service.
- Outbound bindings resolve operational peers through a DNS-SD `IOperationalPeerResolver`.
- Bridged endpoint ids must stay stable when node configuration changes. A test enforces this.
- `MatterBridgeService` is split as part of [M3](../plans/m03-split-oversized-classes.md).

## Consequences

- Scheduled in roadmap phase 3, together with backlog item 8 and the S10 fixes, which don't depend
  on the security mode.
- The orchestrator needs host networking when Matter is used (the compose `compose.matter.yml`
  override in [design 7.4](../design/operations.md)).

## Alternatives considered

A separate Matter bridge container: rejected for now, because it would need its own copy of the
node and template state the orchestrator already has.
