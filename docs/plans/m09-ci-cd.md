# M9. CI/CD for every repository (backlog item 1)

Applies to: see the problem description. Status: snapshot from the September 2026 platform review. Verify against the code before starting work.
Index and dependencies: [plans/README.md](README.md). Backlog: [open-issues.md](../backlog/open-issues.md).

## Problem (verified in the workflow files)

- **Coverage.** Only `RIoT2.Matter` validates on push and PR (`validate.yml`). Seven other
  repositories only publish, triggered by a `*.*.*` tag, without running tests. Seven have no workflow at all:
  Ard.Shared, Ard.M5Core2.Node, Ard.M5Dial.Node, Ard.WiegandI2C, Net.RasPi.Devices, Mobile and
  Tests. **RasPi.Devices has no release pipeline**, so its plugin zip is built by hand.
- **Cross-repository references.** `RIoT2.Tests` references `../RIoT2.Core`,
  `../RIoT2.Net.Orchestrator` and `../RIoT2.Connector.InfluxDB`. `RIoT2.Net.Node/Tests` references
  `../../RIoT2.Net.Devices`. CI therefore has to check out sibling repositories side by side.
- **Secrets.** One personal access token, `NUGET_PACKAGE_TOKEN`, is used for GHCR login, NuGet push
  and GitHub releases. It is also passed to `docker build` as a build argument. Dockerfiles write it
  into `nuget.config` with `--store-password-in-clear-text`, so it ends up in an image layer. The UI
  workflow passes it even though the UI build doesn't use NuGet.
- **Fragile steps:**
  - Core builds with `setup-dotnet 8.0.x`.
  - The Devices release hard-codes `/home/runner/work/...` paths and a list of 22 DLL names, and
    uses the deprecated `actions/create-release@v1` and `upload-release-asset@v1`.
  - Node and Orchestrator inject `Manifest.json` with `docker create`/`docker cp`/`docker commit`
    after the build.

## Design

1. **Reusable workflows** in this repository under `.github/workflows/`. Callers use
   `Revolutionized-IoT2/.github/.github/workflows/<name>.yml@main`.

   | Workflow | Inputs | Does |
   |---|---|---|
   | `dotnet-validate.yml` | `projects`, `dotnet-version` (default `10.0.x`), `siblings` (repositories to check out next to this one), `test-filter` | restore, build with `CI=true`, test, upload TRX results |
   | `node-validate.yml` | `working-directory` | `npm ci`, `typecheck`, `test`, `build` |
   | `firmware-validate.yml` | `envs` | `pio run` for each environment. Runs the `RIoT2.Ard.Shared/tests` native tests with `g++` on `ubuntu-latest`, which fixes "native tests can't run" from section 1. Uploads the `.bin` files. |
   | `docker-publish.yml` | `image`, `dockerfile`, `platforms`, `version` | Buildx with BuildKit secret `nuget_token`, OCI labels, tags `<version>` and `latest` (`-arm64v8` variants for the node), SBOM and provenance attestations ([backlog item 9](../backlog/open-issues.md)) |
   | `nuget-publish.yml` | `projects`, `version` | pack with `-p:Version`, push to GitHub Packages |
   | `plugin-release.yml` | `project`, `version` | `dotnet publish`; zip the **whole** publish folder minus host-provided assemblies (`RIoT2.Core*.dll`, `Microsoft.Extensions.*` and the shared framework, matching `PluginLoadContext`'s shared list); write `PluginManifest.json` (with `coreVersion`), `<zip>.sha256` ([7.2](../design/desired-state-configuration.md)) and, later, `.sig` ([7.5](../design/security-mode.md)); create the release with `softprops/action-gh-release` |
   | `firmware-release.yml` | `envs`, `version` | builds, attaches `firmware-<env>-<version>.bin` and an OTA manifest to the release |

2. **Per-repository callers.** `ci.yml` runs on `push` and `pull_request`. `release.yml` runs on a
   `*.*.*` tag or `workflow_dispatch`, and calls validate **before** publish. Sibling checkouts
   (`actions/checkout` with `repository:` and `path: ../<repo>`) use `main`, or the same tag name if
   it exists.

   | Repository | ci.yml | release.yml |
   |---|---|---|
   | Core | dotnet-validate | nuget-publish |
   | Matter | dotnet-validate (replaces `validate.yml`), node-validate (Controller UI) | nuget-publish (Matter, then ControlBridge) |
   | Orchestrator, Node, Influx, Elsa | dotnet-validate (Node with sibling Devices) | docker-publish (Node: amd64 and arm64) |
   | Devices, RasPi.Devices | dotnet-validate | plugin-release (**new** for RasPi) |
   | Tests | dotnet-validate with siblings Core, Orchestrator, Influx; also nightly | – |
   | UI | node-validate | docker-publish |
   | Mobile | dotnet-validate for `Tests/` on Linux; Android build on `windows-latest` weekly | Android artifact (APK/AAB) on tag |
   | Ard.Shared, M5Core2, M5Dial | firmware-validate | firmware-release (both boards) |
   | Ard.WiegandI2C | Arduino CLI compile for ATtiny85 (add a minimal `platformio.ini` or `arduino-cli` step) | release `.hex` |
   | .github | `docker compose config` for `deploy/` ([7.4](../design/operations.md)), markdownlint | – |

3. **Secrets.**
   - Use `GITHUB_TOKEN` with job-level `permissions` (`packages: write`, `contents: write`,
     `id-token: write` for attestations) for GHCR, GitHub Packages and releases.
   - Give each consuming repository read access to the `RIoT2.Core`/`RIoT2.Matter` packages in the
     package settings ("Manage Actions access"), so restores work with `GITHUB_TOKEN`.
   - Keep one read-only `PACKAGES_READ_TOKEN` only as a fallback if a cross-repository restore can't
     use `GITHUB_TOKEN`. Retire `NUGET_PACKAGE_TOKEN`.
4. **Dockerfiles** take the feed token through `RUN --mount=type=secret,id=nuget_token` and write
   `nuget.config` inside that single `RUN`, so it never persists in a layer. `ARG NUGET_AUTH_TOKEN`
   is removed. The version comes from a build argument: the final stage writes `Manifest.json` and
   sets `org.opencontainers.image.version`, replacing the `docker commit` steps.
5. **Dependency updates.** Add a Renovate configuration (`renovate.json` in each repository,
   presets in this repository) covering NuGet, npm, Dockerfile, GitHub Actions and PlatformIO.
   Renovate supports all five; Dependabot doesn't support PlatformIO. It also pins base-image
   digests (backlog item 9).
6. **Branch protection** on `main`: require `ci.yml` to pass.

## Phases

| Phase | Content |
|---|---|
| C1 | `dotnet-validate`, `node-validate`, `firmware-validate` and the `ci.yml` callers in every repository |
| C2 | `docker-publish` with BuildKit secrets and version build argument; replace the five Docker workflows and remove `docker commit` |
| C3 | `plugin-release` for Devices and the new RasPi pipeline, with the `.sha256` sidecar |
| C4 | `nuget-publish` for Core and Matter, then `firmware-release` and Mobile artifacts |
| C5 | Renovate, branch protection, retire `NUGET_PACKAGE_TOKEN` |

## Done when

- Every repository runs CI on PR.
- `docker history` of each published image shows no token.
- Every release asset is produced by a reusable workflow.
- RasPi.Devices has a published plugin zip.
