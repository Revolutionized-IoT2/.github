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

These can't be done in code. Status checked on 2026-10-03.

| ID | Action | Status |
|---|---|---|
| MA1 | Rotate leaked credentials and scrub them from git history | **Open, tooling ready (2026-10-12).** A full-history scan finds two real leaks: the Netatmo credentials in Orchestrator `bin/` and the Matter controller secret. The code fixes are pushed; rotating Netatmo and running the scrub script remain. Details below. |
| MA2 | Cut a Core release and align all consumers | **Done 2026-10-03.** Core `1.0.1` is published on GitHub Packages. It carries the `0.1.44` security fixes and the .NET 10 dependencies ([M8](../plans/m08-dotnet10-migration.md)), and every consumer references it. Tag `1.0.0` failed CI and was never published. Versions `0.1.40`–`0.1.42` have no git tag either. The consumers' own releases are the remaining steps of MA3. |
| MA3 | Release the .NET 10 builds in order | **Almost done (2026-10-12).** Core, Matter, Orchestrator, Elsa, Node, Devices, RasPi.Devices and UI are released on .NET 10. Still to do: the InfluxDB connector tag, a Mobile build, and upgrading the installation. Deadline: 10 November 2026. Details below. |
| MA4 | Read the upgrade notes before deploying the new images | See [guides/upgrading.md](../guides/upgrading.md). |

### MA1. Rotate the leaked credentials and scrub them from git history

On 2026-10-12, [tools/secret-scan](../../tools/secret-scan/README.md) scanned every commit of every
repository (local history matched GitHub). Status per repository:

| Repository | What is in history | Status |
|---|---|---|
| `RIoT2.Net.Orchestrator` | `bin/Debug/net9.0/StoredObjects/**`: a real Netatmo `clientId`, `clientSecret`, access token and refresh token. No other credentials. | **Rotate, then scrub.** The files are untracked and `bin/` is ignored. The scrub rule drops `bin/` from history; a dry run keeps all 20 tags and the current tree. |
| `RIoT2.Matter` | `Controller/appsettings.json`: the controller's `MatterController:CredentialProtectionSecret`. Only the standalone Controller host uses it; the Orchestrator's Control Bridge uses its own generated `FabricStoreKey`. | **Fixed in code, then scrub.** The value is blank now and comes from user secrets. Recreate any local Controller credential store under a new secret, then run the scrub rule. |
| `RIoT2.Mobile` | `Platforms/Android/google-services.json`: the Firebase client API key. It ships in every APK and isn't a server secret. | **Restrict it** in Google Cloud to the Android package and signing SHA. It is allowlisted in `.gitleaks.toml`; no scrub. |
| `RIoT2.Elsa` | Older `Program.cs` versions set the identity signing key to Elsa's public documentation placeholder. | **Nothing to scrub.** Production now refuses to start without `ELSA_IDENTITY_SIGNING_KEY`. Set a strong value. |
| `RIoT2.Connector.InfluxDB` | No token in any commit. The earlier note about `Properties/launchSettings.json` was wrong: the committed versions hold no credentials. | **Nothing to scrub.** Rotate the token only if it was ever shared another way. |
| All other repositories | Nothing found. | Clean. |

What to do:

1. Revoke and reissue the Netatmo app secret and tokens, and update the Netatmo device in the
   orchestrator UI.
2. Restrict the Firebase API key, and set a strong `ELSA_IDENTITY_SIGNING_KEY`.
3. The open changes in Orchestrator and Matter were pushed on 2026-10-12. Run
   `scrub-history.ps1 -Repository <name>` for both. Check the output, run it again with `-Push`,
   and re-sync the working copies ([how](../../tools/secret-scan/README.md#scrub-a-leaked-credential-from-history)).
   The rewrite also moves the existing tags (such as `1.0.0`) to new commit IDs; the published
   images and packages are unaffected.
4. Run `scan.ps1`. It must report no findings. Then close MA1.

This is needed even on an isolated network: the repositories are public, so anyone can use the
Netatmo credentials directly.

### MA2. Cut a Core release and align all consumers

**Done 2026-10-03** with Core `1.0.1`. Kept for the release rule below.

- The security fixes in Core (serialization binder, zip-slip guard) only reach the consumers once
  every `PackageReference` points to the new release.
- A compatibility build in September 2026 confirmed that no consumer needs code changes.
- After bumping, release the Node image and the Devices plugin zip together
  ([overview § Versioning](../architecture/overview.md#versioning-and-releases)).

### MA3. Release the .NET 10 builds in order

- .NET 8 and .NET 9 reach end of support on 10 November 2026. The code of every .NET repository
  targets `net10.0` (Core stays `netstandard2.0`), with 10.0 images and `setup-dotnet 10.0.x`
  ([M8](../plans/m08-dotnet10-migration.md)).
- Release in this order. Each step restores packages that the previous step publishes. A `net10.0`
  plugin can't load into a `net9.0` node; a `net9.0` plugin still loads into a `net10.0` node.
  Status on 2026-10-12, checked against the tags and release workflow runs:

| Step | Component | Release | Status |
|---|---|---|---|
| 1 | Core | `1.0.1` (NuGet) | Done 2026-10-03; this also completed MA2. Tag `1.0.0` failed CI. |
| 2 | Matter and ControlBridge | `1.0.0` (NuGet) | Done 2026-10-03. Developed as `0.1.15`; the tag sets the package version. |
| 3 | Orchestrator | `1.0.0` image | Done 2026-10-12, on Matter `1.0.0`. |
| 3 | Elsa | `1.0.1` image | Done 2026-10-12. Tag `1.0.0` failed the Docker build (Alpine `protoc`). |
| 3 | InfluxDB connector | image | **Open.** The code is ready (`net10.0`, Core `1.0.1`, builds). Push tag `1.0.0`. |
| 4 | Node (amd64, arm64) | `1.0.0` images | Done 2026-10-12. |
| 4 | Devices plugin | `1.0.0` zip | Done 2026-10-12, as a GitHub release asset. |
| 4 | RasPi.Devices plugin | `1.0.0` tag | Tagged. There is no release workflow, so the plugin is built and copied by hand (I03 adds CI). |
| 5 | UI | `1.0.1` image | Done 2026-10-12. Tag `1.0.0` failed the Docker build (missing `vite-plugin-vuetify`). |
| 5 | Mobile | APK | **Open.** MAUI 10 with Android API 36; the unit tests pass. Building the APK needs the Android SDK platform 36 (`dotnet build -t:InstallAndroidDependencies -f net10.0-android`). There is no release workflow. |

To finish, push the InfluxDB tag, build and install the Mobile app, then upgrade the installation
with the [upgrade notes](../guides/upgrading.md) (MA4) and close MA3 and I02.

```powershell
git -C C:\Src\RIoT2\RIoT2.Connector.InfluxDB tag 1.0.0
git -C C:\Src\RIoT2\RIoT2.Connector.InfluxDB push origin 1.0.0
```

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
