# Architecture decision records

Applies to: all RIoT2 repositories.

An ADR records one significant decision: the context, the decision, and its consequences. ADRs are
append-only. To change a decision, add a new ADR that supersedes the old one and update the old
one's status line. Don't rewrite history.

## When to write one

- A choice that constrains more than one repository (contracts, security model, runtime, tooling).
- A choice that someone (human or AI) is likely to "fix" later without knowing why it was made.
- Accepting or rejecting a proposal from [architecture/target.md](../architecture/target.md) or a
  [design](../design/README.md).

## How

1. Copy [0000-template.md](0000-template.md) to `NNNN-short-kebab-title.md` using the next free number.
2. Fill it in. Keep it under one screen where possible; link to designs instead of copying them.
3. Add a row to the index below.

## Index

| ADR | Title | Status |
|---|---|---|
| [0001](0001-documentation-structure.md) | Documentation structure and AI instruction files | Accepted |
| [0002](0002-isolated-network-security-model.md) | Isolated single-user network security model | Accepted |
| [0003](0003-elsa-sole-automation-engine.md) | Elsa 3 is the only automation engine | Accepted |
| [0004](0004-optional-security-mode.md) | Optional, switchable security mode (A1) | Accepted |
| [0005](0005-split-core-packages.md) | Split Core into a contract package and runtime packages (A2) | Accepted |
| [0006](0006-reliable-delivery.md) | Reliable delivery with an outbox, TTL and command results (A3) | Accepted |
| [0007](0007-desired-state-configuration.md) | Desired-state configuration and verified plugin installs (A4) | Accepted |
| [0008](0008-automation-provider-interface.md) | Automation behind an `IAutomationProvider` interface (A5) | Accepted |
| [0009](0009-connector-sdk.md) | Connector SDK, with Influx as the reference connector (A6) | Accepted |
| [0010](0010-finish-matter-integration.md) | Finish the Matter integration inside the orchestrator (A7) | Accepted |
| [0011](0011-firmware-noderuntime.md) | Shared firmware NodeRuntime in RIoT2.Ard.Shared (A8) | Accepted |
| [0012](0012-operations-first-class.md) | First-class operations: compose stack, logging, metrics, backup (A9) | Accepted |
| [0013](0013-unified-engineering-practices.md) | Unified engineering practices across .NET repositories (A10) | Accepted |
| [0014](0014-device-plugin-sdk.md) | Device plugin SDK built on RIoT2.Core.Devices | Accepted |
| [0015](0015-system-text-json-typed-persistence.md) | System.Text.Json only, with typed persistence (M2) | Accepted |

ADRs 0004–0013 accept the target architecture items A1–A10. Accepted means the direction is
decided; the work itself is scheduled in the [roadmap](../../ROADMAP.md) and is not implemented
until the roadmap item is ticked.
