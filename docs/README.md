# RIoT2 platform documentation

Applies to: the whole RIoT2 platform. This is the index. Each document covers one topic and names
its source of truth in code.

## Read by task

| If you want to… | Read |
|---|---|
| Understand the platform | [architecture/overview.md](architecture/overview.md) |
| Work on anything as an AI agent | [../AGENTS.md](../AGENTS.md), then the target repository's `AGENTS.md` |
| Change or consume MQTT messages | [contracts/mqtt-topics.md](contracts/mqtt-topics.md) |
| Call or add HTTP/gRPC endpoints | [contracts/http-api.md](contracts/http-api.md) |
| Deploy, or add an environment variable, port or volume | [contracts/env-vars.md](contracts/env-vars.md) |
| Change node/device configuration, templates, persistence or plugins | [contracts/configuration.md](contracts/configuration.md) |
| Know why something is the way it is | [adr/](adr/README.md) |
| Install and run the platform | [profile/README.md § Getting started](../profile/README.md#getting-started) (moves to `guides/` later) |
| See open issues, proposals and the roadmap | [PLATFORM-REVIEW.md](../PLATFORM-REVIEW.md) (to be split into issues, ADRs and a roadmap) |

## Contents

```text
.github/
  AGENTS.md                      Workspace guide for AI agents: repo map, commands, platform rules
  README.md                      What this repository contains
  profile/README.md              Organization landing page (GitHub profile)
  PLATFORM-REVIEW.md             2026-09 cross-repository review (to be split up)
  docs/
    README.md                    This index
    architecture/overview.md     Concepts, components, topology, flows, versioning
    contracts/mqtt-topics.md     Topics, payloads, lifecycle, delivery semantics
    contracts/http-api.md        REST and gRPC endpoints of every component
    contracts/env-vars.md        Environment variables, ports, volumes, images
    contracts/configuration.md   Configuration JSON, StoredObjects, plugins
    adr/                         Architecture decision records
```

Planned (not created yet):

- `guides/`: getting started, deployment, upgrading and security model, moved out of
  `profile/README.md`.
- `ROADMAP.md`: from PLATFORM-REVIEW section 9.

## Conventions

- **Code references** are written as `<Repository>/<path>`, for example `RIoT2.Core/Constants.cs`.
  - Locally, the path is relative to the workspace root (`C:\Src\RIoT2`).
  - On GitHub, it is `https://github.com/Revolutionized-IoT2/<Repository>/blob/main/<path>`.
  - Line numbers are deliberately left out, because they go stale.
- **Source of truth**: every document names the code it describes. When they disagree, the code
  wins and the document is fixed. Intentional or not-yet-fixed differences are listed under
  "Known divergences" in the document.
- **Planned vs. implemented**: anything not in the code yet is under a "Planned (not
  implemented)" heading. Never document a proposal as current behaviour.
- **Snapshots**: values that change often (framework versions, Core package versions) are marked
  as snapshots with a date.

## Maintaining these docs

- Update a contract document in the same change that alters the contract, in whichever
  repository that is.
- Keep files under about 15 KB. Split by topic rather than growing a file. AI tools read files in
  chunks of about 20 KB.
- Before committing, check that relative links resolve and that no file has grown past the limit.
  There is no automated check yet; one is planned.
- Rules for per-repository documents are in [ADR 0001](adr/0001-documentation-structure.md).
