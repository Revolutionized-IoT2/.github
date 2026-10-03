# RIoT2 platform documentation

Applies to: the whole RIoT2 platform. This is the index. Each document covers one topic and names
its source of truth in code.

## Read by task

| If you want to… | Read |
|---|---|
| Understand the platform as it is | [architecture/overview.md](architecture/overview.md) |
| Work on anything as an AI agent | [../AGENTS.md](../AGENTS.md), then the target repository's `AGENTS.md` |
| Change or consume MQTT messages | [contracts/mqtt-topics.md](contracts/mqtt-topics.md) |
| Call or add HTTP/gRPC endpoints | [contracts/http-api.md](contracts/http-api.md) |
| Deploy, or add an environment variable, port or volume | [contracts/env-vars.md](contracts/env-vars.md) |
| Change node/device configuration, templates, persistence or plugins | [contracts/configuration.md](contracts/configuration.md) |
| Know why something is the way it is | [adr/](adr/README.md) |
| Install and run the platform | [guides/getting-started.md](guides/getting-started.md), then [guides/first-configuration.md](guides/first-configuration.md) |
| Deploy variations (Raspberry Pi, ESP32, InfluxDB, Matter) or operate | [guides/deployment.md](guides/deployment.md) |
| Upgrade an existing deployment | [guides/upgrading.md](guides/upgrading.md) |
| Understand the security model | [guides/security.md](guides/security.md) |
| Pick up work | [../ROADMAP.md](../ROADMAP.md), then [backlog/](backlog/README.md) |
| Implement a planned change | [plans/](plans/README.md) (maintainability) or [design/](design/README.md) (architecture) |
| See where the architecture is heading | [architecture/target.md](architecture/target.md) |
| Propose a feature | [features.md](features.md) |

## Contents

```text
.github/
  AGENTS.md                        Workspace guide for AI agents: repo map, commands, platform rules
  README.md                        What this repository contains
  ROADMAP.md                       Phased order of work, with links to backlog, plans and designs
  PLATFORM-REVIEW.md               Redirect: old review sections and IDs → new locations
  profile/README.md                Organization landing page (GitHub profile)
  docs/
    README.md                      This index
    guides/                        Getting started, first configuration, deployment, security, upgrading
    architecture/overview.md       Current: concepts, components, topology, flows, versioning
    architecture/target.md         Proposed: target shape and proposals A1–A10
    contracts/mqtt-topics.md       Topics, payloads, lifecycle, delivery semantics
    contracts/http-api.md          REST and gRPC endpoints of every component
    contracts/env-vars.md          Environment variables, ports, volumes, images
    contracts/configuration.md     Configuration JSON, StoredObjects, plugins
    adr/                           Architecture decision records (accepted decisions)
    backlog/                       Maintainer actions, open issues 1–22, optional hardening S1–S12
    plans/                         Maintainability plans M1–M11, one file each
    design/                        Designs 7.1–7.5 (reliable delivery, desired state, connectors, ops, security)
    features.md                    Unscheduled feature ideas
    reviews/                       Frozen review records (history, not current state)
  tools/ui-screenshots/            Reproducible capture of the UI screenshots in docs/guides/images
  tools/docs-check/                Docs drift check (links, layout, secrets, contracts vs code), also in CI
  .github/workflows/docs-check.yml CI for the drift check: hub changes, weekly, reusable by other repos
```


## ID registry

IDs are stable. Use them in commits, issues and other documents.

| ID | Kind | Location |
|---|---|---|
| `ADR NNNN` | Accepted decision | [adr/](adr/README.md) |
| `A1`–`A10` | Architecture proposal | [architecture/target.md](architecture/target.md) |
| `7.1`–`7.5` | Design ("design 7.2 phase 0") | [design/](design/README.md) |
| `M1`–`M11` | Maintainability plan ("M8 step 3") | [plans/](plans/README.md) |
| `1`–`22` | Open issue ("backlog item 18") | [backlog/open-issues.md](backlog/open-issues.md) |
| `S1`–`S12` | Optional hardening item | [backlog/optional-hardening.md](backlog/optional-hardening.md) |
| `MA1`–`MA4` | Maintainer action (outside code) | [backlog/README.md](backlog/README.md#maintainer-actions) |
| `D1`–`D5`, `C1`–`C2` | Contract divergence | [contracts/mqtt-topics.md](contracts/mqtt-topics.md#known-divergences), [contracts/configuration.md](contracts/configuration.md#known-divergences) |

Security mode *phases* in design 7.5 are also called `S0`–`S6`. Say "phase S1" or "item S1" to
make clear which one you mean.

## Conventions

- **Code references** are written as `<Repository>/<path>`, for example `RIoT2.Core/Constants.cs`.
  - Locally, the path is relative to the workspace root (`C:\Src\RIoT2`).
  - On GitHub, it is `https://github.com/Revolutionized-IoT2/<Repository>/blob/main/<path>`.
  - Line numbers are deliberately left out, because they go stale.
- **Links from other repositories** to this hub, or between repositories, use absolute GitHub
  URLs, because relative links don't work across repositories on GitHub. Links inside one
  repository are relative.
- **Source of truth**: every document names the code it describes. When they disagree, the code
  wins and the document is fixed. Intentional or not-yet-fixed differences are listed under
  "Known divergences" in the document.
- **Current vs. proposed**:
  - `architecture/overview.md` and `contracts/` describe what the code does now.
  - `architecture/target.md`, `design/`, `plans/` and `features.md` describe proposals.
  - In current-state documents, anything not yet in the code goes under a "Planned (not
    implemented)" heading. Never document a proposal as current behaviour.
- **Snapshots**: values that change often (framework versions, Core package versions, backlog
  descriptions) are marked as snapshots with a date. Verify them before acting on them.
- **Images** are screenshots of the current UI, stored next to the document that uses them. Each
  one must show current behaviour; delete images that no longer do. The profile walkthrough images
  are regenerated with [tools/ui-screenshots](../tools/ui-screenshots/README.md).

## Maintaining these docs

- Update a contract document in the same change that alters the contract, in whichever
  repository that is.
- When work finishes:
  1. Remove the item from the backlog.
  2. Tick it in the roadmap.
  3. Move any contract change from the design into `contracts/`.
- Keep files under about 15 KB. Split by topic rather than growing a file. AI tools read files in
  chunks of about 20 KB.
- Before committing documentation or contract code, run the drift check from the workspace root:
  `python .github\tools\docs-check\check_docs.py`. It checks:
  - links, anchors and images;
  - sizes and the per-repository layout;
  - leaked local values;
  - MQTT topics, enums, variables, HTTP routes, the `.proto` files and code references against
    the code.

  CI runs it on every hub change and weekly
  ([tools/docs-check](../tools/docs-check/README.md)).
- Rules for per-repository documents are in [ADR 0001](adr/0001-documentation-structure.md).