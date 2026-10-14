# Designs

Applies to: the whole platform. Detailed designs for the larger architecture items. All of them
were **accepted on 2026-10-12**; each design's status line says which phases are implemented. They
were written for the September 2026 platform review, and their "current behaviour" sections
describe the code at that time.

| ID | Design | Item | Decision | Roadmap |
|---|---|---|---|---|
| 7.1 | [Reliable delivery](reliable-delivery.md): outbox, command results, QoS 1 | A3, A5 | [ADR 0006](../adr/0006-reliable-delivery.md), [ADR 0008](../adr/0008-automation-provider-interface.md) | Phases 1–3 |
| 7.2 | [Desired-state configuration and plugin updates](desired-state-configuration.md): revision and hash, status topic, verified plugins | A4 | [ADR 0007](../adr/0007-desired-state-configuration.md) | Phases 1–3 |
| 7.3 | [Connector SDK](connector-sdk.md): shared connector runtime; Influx becomes the reference connector | A6 | [ADR 0009](../adr/0009-connector-sdk.md) | Phase 3 |
| 7.4 | [Operations](operations.md): compose stack, logging, metrics, backup and restore | A9 | [ADR 0012](../adr/0012-operations-first-class.md) | Phases 1–3 |
| 7.5 | [Optional security mode](security-mode.md): `RIOT2_SECURITY_MODE=off\|audit\|on` | A1 | [ADR 0004](../adr/0004-optional-security-mode.md) | Phase 2 (seams), optional |

The architecture items are described in [architecture/target.md](../architecture/target.md),
and scheduling is in [ROADMAP.md](../../ROADMAP.md). Each design phase is assigned to a delivery
increment in [increments/](../increments/README.md). The ADR states the binding rules; the design
holds the details. The "Open points" in each design have chosen defaults and may still be adjusted
during implementation without a new ADR, as long as the ADR rules hold.

While a design is being implemented:

1. Move the parts that change a contract into [contracts/](../contracts/) in the same change.
2. Once a design is fully implemented, either delete it or mark it **Implemented** with a date.
   The contract documents then describe the behaviour.
3. A change to a rule stated in the ADR needs a new ADR that supersedes it.
