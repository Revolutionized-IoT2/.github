# RIoT2 roadmap

Applies to: all repositories. This file covers the order of work only, as
[delivery increments](docs/increments/README.md) `I01`–`I54`. Each increment ends with releases
and a working installation. Its scope, dependencies and "Done when" checks are in the increment
files. The work itself is described in:

| What | Where | IDs |
|---|---|---|
| Delivery increments | [docs/increments/](docs/increments/README.md) | I01–I54 |
| Open issues | [docs/backlog/](docs/backlog/README.md) | 1–24, S1–S12 |
| Implementation plans | [docs/plans/](docs/plans/README.md) | M1–M12 |
| Designs | [docs/design/](docs/design/README.md) | 7.1–7.5 |
| Architecture items and decisions (accepted 2026-10-12) | [docs/architecture/target.md](docs/architecture/target.md), [ADRs](docs/adr/README.md) | A1–A10, ADR 0004–0015 |
| Feature ideas | [docs/features.md](docs/features.md) | — |

When an increment is done, tick it here with a date and follow the
[definition of done](docs/increments/README.md#definition-of-done-every-increment). Some
decisions were taken on 2026-10-12 without the maintainer and still need confirming. They're
listed under [decisions to confirm](docs/increments/README.md#decisions-to-confirm).

## Already done

- [x] Core `1.0.1` released and every consumer aligned on it
  ([MA2](docs/backlog/README.md#ma2-cut-a-core-release-and-align-all-consumers)), 2026-10-03.
- [x] .NET 10 migration in code ([M8](docs/plans/m08-dotnet10-migration.md) steps 1–8 and 11),
  2026-10-03. The releases are I02.

## Phase 0: release (before 10 November 2026)

- [x] I01 Secrets and publish hygiene, 2026-10-12.
- [x] I02 .NET 10 release train, 2026-10-12.

## Phase 1: quality baseline

Details: [phase-0-1.md](docs/increments/phase-0-1.md).

- [x] I03 CI for every repository, 2026-10-14 (released 2026-10-12, required checks MA5 2026-10-13).
- [x] I04 Restart only changed devices, 2026-10-12 (Core `1.1.0`, Node and Orchestrator `1.0.2`).
- [x] I05 Golden files and route contract, 2026-10-13.
- [x] I06 In-process end-to-end harness, 2026-10-13.
- [x] I07 Typed configuration, 2026-10-13 (Core `1.2.0`; Orchestrator, Node, Elsa and InfluxDB connector `1.1.0`).
- [x] I08 MQTT client robustness, 2026-10-13 (Core `1.3.0`; Orchestrator, Node, Elsa and InfluxDB connector `1.2.0`).
- [x] I09 Async cleanup, part 1, 2026-10-13 (Core `1.4.0`, Node `1.2.1`, Devices and RasPi.Devices `1.1.0`).
- [x] I10 Plugin configuration and conformance, 2026-10-14 (Core `1.5.0`, Node `1.3.0`, Devices and RasPi.Devices `1.2.0`).
- [x] I11 Durable workflow delivery, 2026-10-14 (Elsa `1.3.0`, Orchestrator `1.3.0`).
- [x] I12 One-command install, 2026-10-14 (`deploy/` compose files; UI `1.1.0`, Node and Orchestrator `1.3.1`).
- [x] I13 Firmware OTA rollback, 2026-10-14 (M5Core2 and M5Dial `0.2.0`; the one-board rollback test is maintainer action MA6).

## Phase 2: platform

Details and parallel tracks: [phase-2.md](docs/increments/phase-2.md).

- Protocol:
  - [x] I14 Additive contract release, 2026-10-14 (Core `1.6.0`).
  - [ ] I15 Command results and API v2
  - [ ] I16 Desired-state configuration for .NET nodes
- Firmware:
  - [ ] I17 Firmware view models
  - [ ] I18 Firmware NodeRuntime
  - [ ] I19 Firmware results and desired state
- Operations:
  - [ ] I20 Consistent logging
  - [ ] I21 Backup and restore
  - [ ] I22 Metrics
- Structure:
  - [ ] I23 Orchestrator restructure
  - [ ] I24 UI restructure and fixes
  - [ ] I25 System.Text.Json on the wire ([ADR 0015](docs/adr/0015-system-text-json-typed-persistence.md))
  - [ ] I26 Typed persistence
  - [ ] I27 Core package split
  - [ ] I28 Narrow references and generated models
- Plugins:
  - [ ] I29 Plugin packaging
  - [ ] I30 Typed device options
- Quality:
  - [ ] I31 Async cleanup, part 2, and threading analyzers
  - [ ] I32 Nullable reference types
  - [ ] I33 Supply chain
- [ ] I34 Security seams with the mode fixed at `off`

## Phase 3: extensibility

Details: [phase-3-4.md](docs/increments/phase-3-4.md).

- [ ] I35 Verified plugin updates
- [ ] I36 Sync and command status in the UI
- [ ] I37 Connector SDK
- [ ] I38 Connector spool
- [ ] I39 Connectors in the UI and a Prometheus exporter
- [ ] I40 Nightly compose smoke test
- [ ] I41 Async-first plugins and the plugin template
- [ ] I42 Wiegand peripheral
- [ ] I43 Matter completion
- [ ] I44 Mobile quick hardening (can be done at any time)
- [ ] I45 Core 2.0: remove compatibility layers

## Phase 4: features

- [ ] I46 System health page
- [ ] I47 Home Assistant connector
- [ ] I48 Elsa activity pack

Other [feature ideas](docs/features.md) are scheduled here when they're picked.

## Optional: when needed

Details: [optional-security.md](docs/increments/optional-security.md). Do these once the system
gets more users, untrusted devices or remote access. Switch each feature on through `audit`
first; it can be switched back to `off` at any time.

- [ ] I49 Security: login, users and API keys
- [ ] I50 Security: realtime gateway
- [ ] I51 Security: MQTT TLS and ACLs
- [ ] I52 Security: endpoints and outbound policy
- [ ] I53 Security: signing and secrets at rest
- [ ] I54 Security: firmware and Mobile
