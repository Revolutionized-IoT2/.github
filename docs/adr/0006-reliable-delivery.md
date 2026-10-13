# 0006. Reliable delivery with an outbox, TTL and command results (A3)

- Status: Accepted
- Date: 2026-10-12
- Applies to: Orchestrator, Elsa, Node, firmware, UI, RIoT2.Core (MQTT client and contracts)

## Context

Workflow triggers to Elsa are dropped on failure, while no workflow node is online, and on restart.
Commands give no feedback and are lost for offline nodes. The .NET MQTT client subscribed at QoS 0,
so delivery was effectively QoS 0 (QoS 1 since Core 1.3.0, I08). See proposal [A3](../architecture/target.md#a3-make-delivery-reliable)
and [design 7.1](../design/reliable-delivery.md).

## Decision

- Orchestrator → Elsa workflow triggers and orchestrator → node commands go through one durable
  SQLite outbox (`StoredObjects/outbox.db`, plain SQL, no EF Core). Node → orchestrator reports
  stay fire-and-forget.
- Delivery is at-least-once with a message id as idempotency key. Receivers must deduplicate.
  Delivery is FIFO per target.
- Every message has a time-to-live (defaults: 300 s for workflow triggers, 30 s for commands) and
  is never retried after it expires. Stale automation counts as a failure.
- MQTT uses QoS 1 for publishing and subscribing everywhere ([M10](../plans/m10-mqtt-client-robustness.md)).
  Clean sessions stay; the outbox is the only place for retry and expiry.
- A command result means "executed without an exception", not "physically confirmed".
- All contract changes are additive and advertised through `capabilities` in the online message,
  so old and new components work together.

## Consequences

- Phase 1 (orchestrator and Elsa only, together with [ADR 0008](0008-automation-provider-interface.md))
  is in roadmap phase 1. Command results and `/api/v2/commands` follow in phase 2.
- The UI can show command status, and failures become visible as metrics and log entries.
- The orchestrator gains a SQLite file that must be included in full-system backups (but not in
  configuration backups).

## Alternatives considered

- Persistent MQTT sessions: rejected, because MQTT 3.1.1 has no message expiry and gives no status.
- A message broker such as RabbitMQ: rejected as too heavy for a single-host home installation.
