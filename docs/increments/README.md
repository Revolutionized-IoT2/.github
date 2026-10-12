# Delivery increments

Applies to: all repositories. This is the order of work, cut into increments that can each be
delivered on their own. The [roadmap](../../ROADMAP.md) lists them by phase with checkboxes;
the details are in the phase files below. Increment IDs `I01`–`I54` are stable. Created
2026-10-12 from the backlog, plans M1–M12, designs 7.1–7.5 and the accepted ADRs.

| File | Increments |
|---|---|
| [phase-0-1.md](phase-0-1.md) | Phase 0 (release) and phase 1 (quality baseline): I01–I13 |
| [phase-2.md](phase-2.md) | Phase 2 (platform): I14–I34 |
| [phase-3-4.md](phase-3-4.md) | Phase 3 (extensibility) and phase 4 (features): I35–I48 |
| [optional-security.md](optional-security.md) | Optional security mode, only when needed: I49–I54 |

## What an increment is

- One to two weeks of part-time work. **S** is up to a week, **M** one to two weeks.
- It ends with tagged releases of every repository it touches, in the release order it states,
  and with the maintainer's own installation upgraded and working.
- It leaves every existing deployment working. Contract changes are additive unless the
  increment says otherwise. Breaking changes are collected in I45 (Core 2.0).

## Definition of done (every increment)

1. The "Done when" checks in the increment pass, with tests in CI once I03 is done.
2. The changed behaviour is described in [contracts/](../contracts/) and the affected
   repositories' README, AGENTS.md and CHANGELOG.md.
3. Breaking deployment steps are in [guides/upgrading.md](../guides/upgrading.md).
4. Finished backlog items are removed from the [backlog](../backlog/README.md), plan steps and
   design phases are marked done, and the increment is ticked in the roadmap with a date.
5. `python .github\tools\docs-check\check_docs.py` passes.

## Rules

- Take the next increment whose dependencies are done. Within a phase, the order in the table
  is the recommended one, but independent increments can be swapped.
- Nullable reference types (I32) may also be enabled project by project in any increment that
  touches a project.
- If an increment turns out larger than M, split it here before starting, and keep the ID for
  the first part (`I15a`, `I15b`).
- Plan steps with no increment: M12 step 7 (hardware package) is done only when a second
  hardware plugin needs it. Feature ideas not listed in phase 4 stay in
  [features.md](../features.md) until scheduled.

## Decisions to confirm

These were decided on 2026-10-12 without the maintainer, picking the most compatible option.
Change them here and in the linked document before the named increment starts.

| Decision | Chosen | Alternative | Needed by |
|---|---|---|---|
| Increment size | 1–2 weeks part-time, each ending in releases | 3–4 week increments | – |
| Plugin `coreVersion` compatibility ([7.2](../design/desired-state-configuration.md#open-points-defaults-chosen)) | Same major; plugin minor ≤ node minor | Exact major.minor match | I35 |
| Default of `wait` in `POST /api/v2/commands` ([7.1](../design/reliable-delivery.md)) | `false` everywhere; only the confirmation activity sets `true` | `true` for Elsa | I15 |
| Removing the Newtonsoft dependency from Core (M2 step 6) | Moved to Core 2.0 (I45), because plugins may use it through Core | In I26 | I26 |

## Index

| ID | Increment | Size | Depends on | Closes or advances |
|---|---|---|---|---|
| I01 | Secrets and publish hygiene | S | – | MA1, item 20 |
| I02 | .NET 10 release train (deadline 10 Nov 2026) | S | I01 | MA3, MA4, item 19 |
| I03 | CI for every repository | M | – | Items 1 and 24, M9 1–4 and 6, M7 1 |
| I04 | Restart only changed devices | S | I03 | Item 18, 7.2 phase 0, D2 |
| I05 | Golden files and route contract | M | I03 | M2 1, M7 2–3, M5 5 |
| I06 | In-process end-to-end harness | M | I04, I05 | Item 17, M7 4 |
| I07 | Typed configuration | S | I03 | Item 14, M4 |
| I08 | MQTT client robustness | M | I06, I07 | Item 3, M10, D4 |
| I09 | Async cleanup, part 1 | S | I08 | Item 4 (part), M11 1–2 |
| I10 | Plugin configuration and conformance | M | I03 | Item 16, item 23 (part), M6, M12 1–2 |
| I11 | Durable workflow delivery | M | I06, I07 | Item 2 (part), 7.1 phase 1, A5 |
| I12 | One-command install | S | I02 | 7.4 phase 1, S12 |
| I13 | Firmware OTA rollback | S | I03, I05 | Item 6, C2 |
| I14 | Additive contract release | S | I05, I08 | 7.1 phase 2 (Core), 7.2 phase 1, `contractVersion` |
| I15 | Command results and API v2 | M | I11, I14 | Item 2 (part), item 7, 7.1 phase 2 |
| I16 | Desired-state configuration (.NET) | M | I04, I06, I14 | 7.2 phases 2–3, D1 |
| I17 | Firmware view models | M | I13 | M5 1–2 |
| I18 | Firmware NodeRuntime | M | I17 | Item 15, M5 3 |
| I19 | Firmware results and desired state | M | I15, I16, I18 | 7.1 phase 3, 7.2 phase 5, D5 |
| I20 | Consistent logging | S | I07 | 7.4 phase 2 |
| I21 | Backup and restore | M | I11, I12 | 7.4 phase 3 |
| I22 | Metrics | M | I12, I20 | 7.4 phase 4 |
| I23 | Orchestrator restructure | M | I05, I15 | Item 13 (part), M3 orchestrator |
| I24 | UI restructure and fixes | M | I05 | Items 10, 13 (part), 21, 22, M3 UI 1–3, D3 |
| I25 | System.Text.Json on the wire | M | I05 | Item 12 (part), M2 2–3 |
| I26 | Typed persistence | M | I21, I25 | Item 12, M2 4–5 |
| I27 | Core package split | M | I10, I26 | Item 11 (part), M1 1–3 |
| I28 | Narrow references and generated models | M | I24, I27 | Item 11 (part), M1 4–5, M3 UI 4 |
| I29 | Plugin packaging | S | I03, I10 | Item 23 (part), M12 3, 7.2 phase 4 (CI) |
| I30 | Typed device options | M | I24, I27 | Item 23 (part), M12 4, C1 |
| I31 | Async cleanup, part 2, and threading analyzers | M | I09 | Item 4, M11 3–4, M8 10 |
| I32 | Nullable reference types | M | I03 | M8 9 |
| I33 | Supply chain | S | I03 | Item 9, M9 5 |
| I34 | Security seams, mode fixed at `off` | M | I07, I12, I15, I30 | 7.5 phase S0 |
| I35 | Verified plugin updates | M | I16, I29 | Item 5, 7.2 phase 4 (node) |
| I36 | Sync and command status in the UI | M | I15, I16, I24 | 7.1 phase 4, 7.2 phase 6 |
| I37 | Connector SDK | M | I05, I08 | 7.3 phase 1 |
| I38 | Connector spool | M | I37 | Item 2, 7.3 phase 2 |
| I39 | Connectors in the UI and a Prometheus exporter | M | I24, I38 | 7.3 phases 3–4 (Prometheus) |
| I40 | Nightly compose smoke test | S | I03, I12 | 7.4 phase 5, M7 5 |
| I41 | Async-first plugins and plugin template | M | I29, I30, I31 | M12 5–6 |
| I42 | Wiegand peripheral | S | I18 | M5 4 |
| I43 | Matter completion | M | I23 | Item 8, A7, S10 |
| I44 | Mobile quick hardening | S | – | S11 (part) |
| I45 | Core 2.0: remove compatibility layers | M | I26, I28, I41 | Item 11, item 23, M1 6, M2 6 |
| I46 | System health page | M | I22, I36 | Feature |
| I47 | Home Assistant connector | M | I15, I39 | 7.3 phase 4 (Home Assistant) |
| I48 | Elsa activity pack | M | I15 | Feature |
| I49 | Security: login, users and API keys | M | I34 | 7.5 phase S1, S1 |
| I50 | Security: realtime gateway | M | I49 | 7.5 phase S2, S2 |
| I51 | Security: MQTT TLS and ACLs | M | I34 | 7.5 phase S3, S3 |
| I52 | Security: endpoints and outbound policy | M | I49 | 7.5 phase S4, S4, S6 (part), S7, S8 |
| I53 | Security: signing and secrets at rest | M | I21, I30, I35 | 7.5 phase S5, S5, S6 (part), S9 (part) |
| I54 | Security: firmware and Mobile | M | I51, I53 | 7.5 phase S6, S9, S11 |
