# Backlog

Applies to: all repositories. This is where open work lives until it is moved to GitHub issues.
Each item keeps its ID from the September 2026 platform review, so existing references stay valid.

| File | Contents | IDs |
|---|---|---|
| This file | [Maintainer actions](#maintainer-actions) (outside code) and [contract divergences](#contract-divergences) found while writing the contract docs | MA1–MA4, D1–D5, C1–C2 |
| [open-issues.md](open-issues.md) | Issues that apply in today's single-user deployment | 1–22 |
| [optional-hardening.md](optional-hardening.md) | Issues that only matter with the optional security mode | S1–S12 |

The fixes are planned in [plans/](../plans/README.md) (M1–M11) and [design/](../design/README.md)
(7.1–7.5), and scheduled in [ROADMAP.md](../../ROADMAP.md).

Working with the backlog:

- Before starting an item, check that it is still open in the code. The descriptions are
  snapshots.
- When an item is done, delete its row (or mark it **Done** with the date and the commit or
  release) and update the roadmap.
- New items get the next free number in their file. If you move an item to a GitHub issue, keep
  its ID in the issue title, for example `[backlog 18] Restart only changed devices`.

## Maintainer actions

These can't be done in code. Status checked on 2026-10-03.

| ID | Action | Status |
|---|---|---|
| MA1 | Rotate leaked credentials and scrub them from git history | **Open.** The files are untracked now, but still in history (Orchestrator `bin/Debug/net9.0/StoredObjects`, InfluxDB `Properties/launchSettings.json`). |
| MA2 | Cut a Core release and align all consumers | **Partly done.** Tag `0.1.44` exists, but the consumers still reference `0.1.41` (Orchestrator, Elsa, Influx) or `0.1.43` (Node, Devices, RasPi). |
| MA3 | Plan the .NET runtime upgrade | Planned as [M8](../plans/m08-dotnet10-migration.md), backlog item 19. Deadline: 10 November 2026. |
| MA4 | Read the upgrade notes before deploying the new images | See [guides/upgrading.md](../guides/upgrading.md). |

### MA1. Rotate the leaked credentials and scrub them from git history

The following were committed to public repositories and are still in history:

- `RIoT2.Net.Orchestrator`: `bin/Debug/net9.0/StoredObjects/**` was tracked. It contains a real
  Netatmo `clientId`, `clientSecret`, access token and refresh token, plus other node
  configuration. The files are now untracked (`git rm --cached`), and `bin/` is ignored.
- `RIoT2.Connector.InfluxDB`: `Properties/launchSettings.json` held a real InfluxDB token.
- `RIoT2.Elsa`: the Elsa identity JWT signing key was hard-coded in `Program.cs`. It now comes
  from `ELSA_IDENTITY_SIGNING_KEY`.
- `RIoT2.Mobile`: `Platforms/Android/google-services.json` contains the Firebase client API key.
  This key is not a server secret, but restrict it to the Android package and signing SHA in
  Google Cloud.

What to do:

1. Revoke and reissue the Netatmo app secret and tokens, the InfluxDB token and the MQTT
   passwords.
2. Remove the files from history (for example `git filter-repo --path <file> --invert-paths`).
3. Force-push.

This is needed even on an isolated network: the repositories are public, so anyone can use the
cloud credentials (Netatmo, InfluxDB) directly.

### MA2. Cut a Core release and align all consumers

- The security fixes in Core (serialization binder, zip-slip guard) only reach the consumers once
  every `PackageReference` points to the new release.
- A compatibility build in September 2026 confirmed that no consumer needs code changes.
- After bumping, release the Node image and the Devices plugin zip together
  ([overview § Versioning](../architecture/overview.md#versioning-and-releases)).

### MA3. Plan the .NET runtime upgrade

- .NET 8 (Influx) and .NET 9 (Orchestrator, Node, plugins, Matter, Mobile) reach end of support
  in November 2026. Elsa already targets .NET 10 LTS.
- Move everything to `net10.0` in one coordinated release: TFMs, Docker base images, CI
  `setup-dotnet`, and the MAUI workloads. Core stays on `netstandard2.0`.
- The step-by-step plan, including the release order that keeps plugins loading, is
  [M8](../plans/m08-dotnet10-migration.md).

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
| C1 | `deviceParameters` keys are camel-cased on download, but devices look them up case-sensitively (for example the `Storage*` keys in `FTP.cs`). **Probable bug.** | [configuration.md](../contracts/configuration.md#known-divergences) |
| C2 | Firmware parses template `type` as a string, so the numeric value is lost | [configuration.md](../contracts/configuration.md#known-divergences) |
