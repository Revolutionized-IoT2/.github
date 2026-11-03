# RIoT2 roadmap

Applies to: all repositories. This file covers the order of work only, as
[delivery increments](docs/increments/README.md) `I01`–`I54`. Each increment ends with releases
and a working installation. Its scope, dependencies and "Done when" checks are in the increment
files. The work itself is described in:

| What | Where | IDs |
|---|---|---|
| Delivery increments | [docs/increments/](docs/increments/README.md) | I01–I54 |
| Open issues | [docs/backlog/](docs/backlog/README.md) | 1–25, S1–S12 |
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
  - [x] I15 Command results and API v2, 2026-10-14 (Core `1.7.0`, Node and Orchestrator `1.4.0`, UI `1.2.0`).
  - [x] I16 Desired-state configuration for .NET nodes, 2026-10-14 (Core `1.8.0`, Node and Orchestrator `1.5.0`).
- Firmware:
  - [x] I17 Firmware view models, 2026-10-14 (M5Core2 and M5Dial `0.3.0`).
  - [x] I18 Firmware NodeRuntime, 2026-10-14 (M5Core2 and M5Dial `0.4.0`).
  - [x] I19 Firmware results and desired state, 2026-11-01 (M5Core2 and M5Dial `0.5.0`).
- Operations:
  - [x] I20 Consistent logging, 2026-11-01 (Core `1.9.0`, Orchestrator and Node `1.6.0`, Elsa `1.4.0`, connector `1.3.0`).
  - [x] I21 Backup and restore, 2026-11-01 (Orchestrator `1.7.0`, UI `1.3.0`, `deploy/` scripts).
  - [x] I22 Metrics, 2026-11-01 (Core `1.10.0`, Orchestrator `1.8.0`, Node `1.7.0`, Elsa `1.5.0`, connector `1.4.0`, `deploy/compose.observability.yml`).
- Structure:
  - [x] I23 Orchestrator restructure, 2026-11-01 (Orchestrator `1.9.0`).
  - [x] I24 UI restructure and fixes, 2026-11-01 (UI `1.4.0`).
  - [x] I25 System.Text.Json on the wire ([ADR 0015](docs/adr/0015-system-text-json-typed-persistence.md)), 2026-11-01 (Core `1.11.0`, Orchestrator `1.10.0`, Node `1.8.0`, Elsa `1.6.0`, connector `1.5.0`).
  - [x] I26 Typed persistence, 2026-11-01 (Core `1.12.0`, Orchestrator `1.11.0`).
  - [x] I27 Core package split, 2026-11-01 (Core `1.13.0` in eight packages, Orchestrator `1.12.0`, Node `1.9.0`).
  - [x] I28 Narrow references and generated models, 2026-11-01 (Core `1.14.1`, Orchestrator `1.13.1`, Node `1.10.0`, Elsa `1.7.1`, connector `1.6.1`, UI `1.5.0`, Devices and RasPi.Devices `1.3.0`).
- Plugins:
  - [x] I29 Plugin packaging, 2026-11-02 (Core `1.15.0` with `RIoT2.Core.Devices.Build`, Devices and RasPi.Devices `1.3.1`).
  - [x] I30 Typed device options, 2026-11-02 (Core `1.16.0`, Node `1.11.0`, Orchestrator `1.14.0`, UI `1.6.0`, Devices `1.4.0`; C1 fixed).
- Quality:
  - [x] I31 Async cleanup, part 2, and threading analyzers, 2026-11-02 (Core `1.16.1`, Node `1.11.1`, Devices `1.5.0`, RasPi.Devices `1.4.0`; analyzers in every .NET repository; backlog item 4 closed).
  - [x] I32 Nullable reference types, 2026-11-02 (Core `1.17.0`, Node `1.12.0`, Orchestrator `1.14.1`, connector `1.6.2`, Devices `1.6.0`, RasPi.Devices `1.5.0`; nullable in every .NET project).
  - [x] I33 Supply chain, 2026-11-02 (Renovate preset in every repository, digest-pinned base images, SBOMs on every release; images Orchestrator `1.14.2`, Node `1.12.1`, Elsa `1.7.2`, connector `1.6.3`, UI `1.6.1`; the Renovate app install is MA7).
- [x] I34 Security seams with the mode fixed at `off`, 2026-11-02 (Core `1.18.0`, Orchestrator `1.15.0`, Node `1.13.0`, Elsa `1.8.0`, connector `1.7.0`, UI `1.7.0`; every endpoint has a policy, `GET /api/security/info`, MQTT TLS, the compose UI uses the `/api` proxy).

## Phase 3: extensibility

Details: [phase-3-4.md](docs/increments/phase-3-4.md).

- [x] I35 Verified plugin updates, 2026-11-02 (Core `1.19.0`, Node `1.14.0`; sidecar hash and `coreVersion` checks, staged install with one rollback; backlog item 5 closed).
- [x] I36 Sync and command status in the UI, 2026-11-02 (Orchestrator `1.16.0`, Elsa `1.9.0`, UI `1.8.0`; sync badge and re-apply, command status, delivery queue, "RIoT Command with confirmation"; designs 7.1 and 7.2 complete).
- [x] I37 Connector SDK, 2026-11-02 (Core `1.20.0` with `RIoT2.Connector.Sdk`, connector `1.8.0`; batching and retry, identical line protocol).
- [x] I38 Connector spool, 2026-11-02 (Core `1.21.0`, connector `1.9.0`; disk spool with replay in order, dead-letter file, shutdown drain to disk, `/health` and spool metrics; backlog item 2 closed).
- [x] I39 Connectors in the UI and a Prometheus exporter, 2026-11-02 (Core `1.22.0`, Orchestrator `1.17.0`, UI `1.9.0`, connector `1.10.0`, new `RIoT2.Connector.Prometheus` `1.0.0`; `NodeType.Connector`, connector list with health, `riot2_value` scraped by the observability profile).
- [x] I40 Nightly compose smoke test, 2026-11-02 (`nightly-smoke.yml`, `tools/compose-smoke`; every health endpoint of the released stack within 2 minutes, failures reported as a `nightly-smoke` issue; design 7.4 and plan M7 complete).
- [x] I41 Async-first plugins and the plugin template, 2026-11-02 (Core `1.23.0`, Node `1.15.0`, Devices `1.7.0`, RasPi.Devices `1.6.0`; `AsyncDeviceBase` no longer blocks, the host calls devices through `DeviceCalls`, `dotnet new riot2-plugin`; plugin authoring guide).
- [x] I42 Wiegand peripheral, 2026-11-02 (M5Core2 and M5Dial `0.6.0`; shared `WiegandI2CPeripheral` reads the WiegandI2C module on Grove PORT.A and reports each card code; plan M5 step 4).
- [x] I43 Matter completion, 2026-11-02 (RIoT2.Matter `1.1.0`, Orchestrator `1.18.0`; outbound bindings through DNS-SD, stable bridged endpoint ids, bounded peer and session tables, constant-time PASE; ADR 0010 done, backlog item 8 and S10 closed).
- [x] I44 Mobile quick hardening, 2026-11-03 (RIoT2.Mobile `1.1.0`; beacon key in `SecureStorage` with migration from `Preferences`, FCM token no longer logged; S11 keeps the host allowlist and HTTPS).
- [x] I45 Core 2.0: remove compatibility layers, 2026-11-03 (Core `2.0.0`, Node, Devices and RasPi.Devices `2.0.0`, Orchestrator `1.19.0`, Elsa `1.10.0`, InfluxDB connector `1.11.0`, exporter `1.1.0`; no facade or Newtonsoft in Core, `RIoT2JsonContext`, every catalog device async with typed options; backlog items 11, 12 and 23 closed).

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
