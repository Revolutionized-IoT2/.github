# Backlog

Applies to: all repositories. This is where open work lives until it is moved to GitHub issues.
Each item keeps its ID from the September 2026 platform review, so existing references stay valid.

| File | Contents | IDs |
|---|---|---|
| This file | [Maintainer actions](#maintainer-actions) (outside code) and [contract divergences](#contract-divergences) found while writing the contract docs | MA1–MA4, D1–D5, C1–C2 |
| [open-issues.md](open-issues.md) | Issues that apply in today's single-user deployment | 1–24 |
| [optional-hardening.md](optional-hardening.md) | Issues that only matter with the optional security mode | S1–S12 |

The fixes are planned in [plans/](../plans/README.md) (M1–M12) and [design/](../design/README.md)
(7.1–7.5), grouped into [delivery increments](../increments/README.md), and scheduled in [ROADMAP.md](../../ROADMAP.md).

Working with the backlog:

- Before starting an item, check that it is still open in the code. The descriptions are
  snapshots.
- When an item is done, delete its row (or mark it **Done** with the date and the commit or
  release) and update the roadmap.
- New items get the next free number in their file. If you move an item to a GitHub issue, keep
  its ID in the issue title, for example `[backlog 18] Restart only changed devices`.

## Maintainer actions

These can't be done in code. Status checked on 2026-10-12.

| ID | Action | Status |
|---|---|---|
| MA1 | Rotate leaked credentials and scrub them from git history | **Done 2026-10-12** (I01). Credentials rotated, histories scrubbed, every repository scans clean. |
| MA2 | Cut a Core release and align all consumers | **Done 2026-10-03.** Core `1.0.1` is published on GitHub Packages. It carries the `0.1.44` security fixes and the .NET 10 dependencies ([M8](../plans/m08-dotnet10-migration.md)), and every consumer references it. Tag `1.0.0` failed CI and was never published. Versions `0.1.40`–`0.1.42` have no git tag either. The consumers' own releases are the remaining steps of MA3. |
| MA3 | Release the .NET 10 builds in order | **Done 2026-10-12** (I02). Every component is released on .NET 10 and the maintainer's installation is upgraded. |
| MA4 | Read the upgrade notes before deploying the new images | Applies to every release. See [guides/upgrading.md](../guides/upgrading.md). |

### MA1. Rotate the leaked credentials and scrub them from git history

**Done 2026-10-12** (increment I01). A gitleaks scan of every commit found two real leaks: the
Netatmo client secret and tokens in Orchestrator `bin/` (committed build output), and the Matter
controller's `CredentialProtectionSecret`. Both values were rotated, and both histories were
rewritten with [tools/secret-scan](../../tools/secret-scan/README.md) and force-pushed; every tag
moved to a new commit ID. The Firebase client key in Mobile is restricted in Google Cloud and
allowlisted, and Elsa refuses to start in Production without `ELSA_IDENTITY_SIGNING_KEY`.

If a credential leaks again, follow the same path: rotate it first, then run `scrub-history.ps1`
(add a rule for the repository) and re-clone or reset every other copy. CI scans every push
([I03](../increments/phase-0-1.md#i03-ci-for-every-repository-m)).

### MA2. Cut a Core release and align all consumers

**Done 2026-10-03** with Core `1.0.1`. Kept for the release rule below.

- The security fixes in Core (serialization binder, zip-slip guard) only reach the consumers once
  every `PackageReference` points to the new release.
- A compatibility build in September 2026 confirmed that no consumer needs code changes.
- After bumping, release the Node image and the Devices plugin zip together
  ([overview § Versioning](../architecture/overview.md#versioning-and-releases)).

### MA3. Release the .NET 10 builds in order

**Done 2026-10-12** (increment I02), before .NET 8 and 9 reach end of support on 10 November
2026. First .NET 10 releases: Core `1.0.1`, Matter and ControlBridge `1.0.0`, Orchestrator
`1.0.0`, Elsa `1.0.1`, InfluxDB connector `1.0.0`, Node `1.0.0` (amd64, arm64), Devices and
RasPi.Devices plugins `1.0.0`, UI `1.0.1`, and the Mobile app (MAUI 10, Android API 36). Elsa
and UI tag `1.0.0` failed their Docker builds and were never published.

The release order still applies to any change that crosses repositories: Core → Matter →
Orchestrator, Elsa, InfluxDB connector → Node images → plugins → UI and Mobile. Each step
restores packages that the previous step publishes, and a plugin can't load into an older node.

## Contract divergences

These were found on 2026-10-03 while the contract documents were checked against the code. The
details are in the linked sections.

| ID | Summary | Details |
|---|---|---|
| D1 | .NET presence messages and last wills aren't retained, but firmware ones are | [mqtt-topics.md](../contracts/mqtt-topics.md#known-divergences) |
| D2 | The orchestrator's last will doesn't clear the retained `riot2/orchestrator/online` | [mqtt-topics.md](../contracts/mqtt-topics.md#known-divergences) |
| D3 | The UI's presence and last-will payloads are PascalCase | [mqtt-topics.md](../contracts/mqtt-topics.md#known-divergences) |
| D4 | .NET publishes at QoS 2 but subscribes at QoS 0 (fixed by M10) | [mqtt-topics.md](../contracts/mqtt-topics.md#known-divergences) |
| D5 | Firmware uses `api/Nodes` (works; cosmetic) | [mqtt-topics.md](../contracts/mqtt-topics.md#known-divergences) |
| C1 | `deviceParameters` keys are camel-cased on download, but devices look them up case-sensitively. This is a latent trap: no active device uses PascalCase keys (the `Storage*` reads in `FTP.cs` are commented out). | [configuration.md](../contracts/configuration.md#known-divergences) |
| C2 | Firmware parses template `type` as a string, so the numeric value is lost | [configuration.md](../contracts/configuration.md#known-divergences) |
