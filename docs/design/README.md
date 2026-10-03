# Designs

Applies to: the whole platform. Detailed designs for the larger architecture proposals. All of
them are **proposed, not implemented**. They were written for the September 2026 platform review,
and their "current behaviour" sections describe the code at that time.

| ID | Design | Proposal | Roadmap |
|---|---|---|---|
| 7.1 | [Reliable delivery](reliable-delivery.md): outbox, command results, QoS 1 | A3, A5 | Phases 1–3 |
| 7.2 | [Desired-state configuration and plugin updates](desired-state-configuration.md): revision and hash, status topic, verified plugins | A4 | Phases 1–3 |
| 7.3 | [Connector SDK](connector-sdk.md): shared connector runtime; Influx becomes the reference connector | A6 | Phase 3 |
| 7.4 | [Operations](operations.md): compose stack, logging, metrics, backup and restore | A9 | Phases 1–3 |
| 7.5 | [Optional security mode](security-mode.md): `RIOT2_SECURITY_MODE=off\|audit\|on` | A1 | Phase 2 (seams), optional |

The proposals are described in [architecture/target.md](../architecture/target.md), and
scheduling is in [ROADMAP.md](../../ROADMAP.md).

When a design is accepted:

1. Record the decision as an [ADR](../adr/README.md).
2. Move the parts that changed a contract into [contracts/](../contracts/).
3. Once a design is fully implemented, either delete it or mark it **Implemented** with a date.
   The contract documents then describe the behaviour.
