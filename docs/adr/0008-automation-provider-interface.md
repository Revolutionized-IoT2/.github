# 0008. Automation behind an `IAutomationProvider` interface (A5)

- Status: Accepted
- Date: 2026-10-12
- Applies to: Orchestrator, Elsa

## Context

The orchestrator calls Elsa's gRPC client (`WorkflowTriggerClient`) directly from its MQTT handling.
That couples it to one engine and makes it hard to test.
[ADR 0003](0003-elsa-sole-automation-engine.md) makes Elsa the only engine. See proposal
[A5](../architecture/target.md#a5-keep-automation-behind-a-provider-interface).

## Decision

- The orchestrator emits domain events (report received, node online, variable changed, and more
  when needed) to an `IAutomationProvider`. It must not call engine clients directly.
- Elsa is the only implementation. It uses the existing gRPC contract and is reached through the
  outbox from [ADR 0006](0006-reliable-delivery.md).
- The interface is not a plugin point for a second engine. ADR 0003 still applies.

## Consequences

- Delivered together with phase 1 of [design 7.1](../design/reliable-delivery.md), in roadmap
  phase 1.
- Orchestrator tests can use a fake provider instead of a gRPC server.

## Alternatives considered

Keeping the direct gRPC call and adding the outbox around it: rejected, because the coupling and
the test difficulty would remain.
