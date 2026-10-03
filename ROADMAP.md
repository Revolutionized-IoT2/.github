# RIoT2 roadmap

Applies to: all repositories. This file covers the order of work only. The work itself is
described in:

| What | Where | IDs |
|---|---|---|
| Open issues | [docs/backlog/](docs/backlog/README.md) | 1–22, S1–S12 |
| Implementation plans | [docs/plans/](docs/plans/README.md) | M1–M11 |
| Designs | [docs/design/](docs/design/README.md) | 7.1–7.5 |
| Architecture proposals | [docs/architecture/target.md](docs/architecture/target.md) | A1–A10 |
| Feature ideas | [docs/features.md](docs/features.md) | — |

The roadmap comes from the September 2026 platform review. When a phase item is done, mark it
here with a date and remove it from the backlog.

## Phase 0: now

- [ ] Rotate secrets and scrub git history ([MA1](docs/backlog/README.md#ma1-rotate-the-leaked-credentials-and-scrub-them-from-git-history)).
- [ ] Align all consumers on the new Core release ([MA2](docs/backlog/README.md#ma2-cut-a-core-release-and-align-all-consumers)).
  Tag `0.1.44` exists. Since M8 all consumers reference `0.1.45`, which still has to be tagged.
- [ ] Release the images, and point operators to the [upgrade notes](docs/guides/upgrading.md).
- [ ] Keep local secrets out of publish output and local Docker images (backlog item 20). This
  is a small `.csproj` and `.dockerignore` change.

## Phase 1: quality baseline

- [x] **.NET 10 migration before 10 November 2026**: [M8](docs/plans/m08-dotnet10-migration.md)
  steps 1–8, backlog item 19. Code done 2026-10-03; release in the order of
  [MA3](docs/backlog/README.md#ma3-release-the-net-10-builds-in-order).
- [ ] CI/CD for every repository: [M9](docs/plans/m09-ci-cd.md), backlog item 1.
- [ ] MQTT client robustness: [M10](docs/plans/m10-mqtt-client-robustness.md), backlog item 3.
- [ ] Remaining async fixes: [M11](docs/plans/m11-async-cleanup.md) steps 1–2, backlog item 4.
  Step 3 continues into phase 2.
- [ ] OTA rollback in firmware (backlog item 6).
- [ ] Contract and integration tests ([M7](docs/plans/m07-contract-integration-tests.md),
  backlog item 17), together with the golden message files they use
  ([M2](docs/plans/m02-system-text-json-persistence.md) step 1).
- [ ] Restart only changed devices (backlog item 18), through
  [design 7.2](docs/design/desired-state-configuration.md) phase 0. This needs no contract change.
- [ ] Durable workflow delivery with the automation provider:
  [design 7.1](docs/design/reliable-delivery.md) phase 1 (Orchestrator and Elsa only).
- [ ] Quick wins:
  - [M4](docs/plans/m04-typed-configuration.md) typed configuration
  - [M6](docs/plans/m06-plugin-configuration-discovery.md) plugin configuration templates
  - a compose stack with `.env.example` ([design 7.4](docs/design/operations.md) phase 1)

## Phase 2: platform

- [ ] One additive Core contract release covering 7.1 phase 2 and 7.2 phase 1. Ship it before
  [M1](docs/plans/m01-split-core-packages.md) starts, so the package split doesn't block it.
- [ ] Command results (7.1 phases 2–3) and desired-state configuration (7.2 phases 2, 3 and 5).
- In parallel:
  - [ ] The remaining [A10](docs/architecture/target.md#a10-unify-engineering-practices) practices:
    M8 steps 9–10 (nullable, threading analyzers). Step 11 (SourceLink) was done 2026-10-03.
  - [ ] M11 steps 3–4.
  - [ ] [M3](docs/plans/m03-split-oversized-classes.md) controller and UI split, with backlog
    items 10 (UI bundle, ESLint), 21 (UI presence) and 22 (UI labels).
  - [ ] M2 System.Text.Json with typed persistence, then the M1 Core package split with
    `contractVersion` ([A2](docs/architecture/target.md#a2-split-core-into-packages)).
  - [ ] Logging, backup/restore and metrics (7.4 phases 2–4).
  - [ ] [M5](docs/plans/m05-firmware-node-runtime.md) firmware view models and `NodeRuntime`.
  - [ ] Image digest pinning and SBOM (backlog item 9).
  - [ ] Security mode phase S0 ([design 7.5](docs/design/security-mode.md)): all seams,
    `/api/security/info` and the nginx `/api` proxy, with the mode fixed at `off`.

## Phase 3: extensibility

- [ ] Verified plugin updates with rollback (7.2 phase 4, backlog item 5).
- [ ] UI sync and command status (7.1 phase 4, 7.2 phase 6).
- [ ] Connector SDK with the Influx spool and a second connector
  ([design 7.3](docs/design/connector-sdk.md) phases 1–4).
- [ ] Nightly compose smoke test (7.4 phase 5).
- [ ] Firmware Wiegand peripheral (M5 step 4, part of
  [A8](docs/architecture/target.md#a8-share-a-firmware-noderuntime)).
- [ ] Matter: the remaining [A7](docs/architecture/target.md#a7-finish-the-matter-integration)
  work, together with backlog item 8 and the S10 fixes, which don't depend on the security mode.
- [ ] Cheap hardening that doesn't depend on the security mode, doable at any time: S11
  (`SecureStorage` for the beacon key) and S12 (`nginx-unprivileged`).

## Phase 4: features

- [ ] [Feature ideas](docs/features.md), starting with the health page, the Home Assistant and
  Prometheus connectors, and the Elsa activity pack.

## Optional: when needed

- [ ] Security mode phases S1–S6 ([design 7.5](docs/design/security-mode.md)) and the
  [optional hardening backlog](docs/backlog/optional-hardening.md). Do this once the system gets
  more users, untrusted devices or remote access.
  - Switch it on through `audit` first, one feature at a time: `api`, `realtime`, `mqtt`,
    `endpoints`, `signing`, `secrets`, `outbound`.
  - It can be switched back to `off` at any time.
