# CI and releases

Applies to: every RIoT2 repository. Introduced by increment
[I03](../increments/phase-0-1.md#i03-ci-for-every-repository-m) (plan [M9](../plans/m09-ci-cd.md)).

Every repository has a `ci.yml` that runs on each push and pull request, and every repository
with a release artifact has a `release.yml` that runs on a `x.y.z` tag. Both are thin callers of
the reusable workflows in this repository, so a build step is fixed once for all repositories.

## Reusable workflows

They live in [.github/workflows](../../.github/workflows) and are called as
`Revolutionized-IoT2/.github/.github/workflows/<file>@main`.

| Workflow | Does | Used by |
|---|---|---|
| `dotnet-validate.yml` | Restore, build (Release, `ContinuousIntegrationBuild`), test with TRX results. Can clone sibling repositories next to the checkout (`siblings`) for `../<repo>` project references or test files, run on several OSes, and fail when the build changes a committed file (`verify-generated`). | Every .NET repository |
| `node-validate.yml` | Optionally clones sibling repositories (`siblings`), then `npm ci` and the listed npm scripts; fails when they change a committed file (`verify-generated`) | UI, Matter Controller UI |
| `firmware-validate.yml` | Clones the four firmware repositories and RIoT2.Core side by side, builds the firmware with PlatformIO, runs the native host tests from `RIoT2.Ard.Shared/tests` with `g++` (including the golden-file test), uploads the images | All `RIoT2.Ard.*` repositories |
| `docker-publish.yml` | BuildKit build of one image for one platform. CI builds without pushing; a release pushes `<tag>` and `latest` (with a suffix such as `-arm64v8`) to GHCR | Orchestrator, Node (amd64 and arm64), Elsa, InfluxDB connector, Prometheus exporter, UI |
| `nuget-publish.yml` | Pack with the tag as version; a release pushes to GitHub Packages. Retries the restore when a package published moments earlier isn't visible yet | Core (then the plugin test kit), Matter (then ControlBridge) |
| `plugin-release.yml` | Publishes a device plugin, whose `RIoT2.Core.Devices.Build` reference writes the node's plugin zip (with `PluginManifest.json`) and a `.sha256` sidecar; checks them (one zip, sidecar, version, no `RIoT2.Core*.dll`) and uploads them; a release attaches them to the GitHub release | Devices, RasPi.Devices |
| `firmware-release.yml` | Validates and builds one firmware project, checks that the tag equals `VERSION`, and attaches `firmware-<env>-<tag>.bin` (or `.hex`), the manifest and `SHA256SUMS` | M5Core2, M5Dial, WiegandI2C |
| `secret-scan.yml` | gitleaks over the whole history, with the repository's `.gitleaks.toml` | Every repository |

The hub's own `ci.yml` runs actionlint on these workflows, markdownlint (`.markdownlint-cli2.jsonc`)
and the secret scan. Change a reusable workflow in a pull request to this repository and check one
caller before merging: every repository uses `@main`.

## Per repository

| Repository | `ci.yml` | `release.yml` on a tag |
|---|---|---|
| Core | build; fails if the build changes `contracts/schemas/` (`verify-generated`); pack smoke test of all ten packages | NuGet, all from the tag: `RIoT2.Core.Contracts`, `.Mqtt`, `.Http`, `.Devices`, `.Node`, the `RIoT2.Core` facade, the plugin test kit `RIoT2.Core.Devices.Testing`, the plugin packer `RIoT2.Core.Devices.Build`, the services' `RIoT2.Core.Hosting` and the connector SDK `RIoT2.Connector.Sdk` |
| Matter | build and test on Linux and Windows, Controller UI, pack both packages | NuGet `RIoT2.Matter`, then `RIoT2.Matter.ControlBridge` against it |
| Orchestrator | build; fails if the build changes `openapi/riot2-orchestrator.json` (`verify-generated`); image build | Image |
| Elsa | build, tests with RIoT2.Core cloned for the golden files, image build | Image |
| InfluxDB connector, Prometheus exporter | build, image build (their tests are in RIoT2.Tests) | Image |
| Node | tests with the Devices catalog cloned next to it, amd64 and arm64 image builds | Both images |
| Devices, RasPi.Devices | build, test, plugin zip as an artifact | Plugin zip and `.sha256` on the GitHub release |
| Tests | the cross-repository suite and the [end-to-end tests](#end-to-end-tests), in Release, against Core, Orchestrator, both connectors, Node and Devices `main`; also nightly | – |
| UI | `npm test` with RIoT2.Core and the Orchestrator cloned (golden files, OpenAPI route test); `npm run build`, which generates the contract models from RIoT2.Core's schema and fails if they change (`verify-generated`); image build | Image |
| Mobile | unit tests; Android APK weekly and on demand | APK and `.sha256` on the GitHub release |
| Ard.Shared, M5Core2, M5Dial, WiegandI2C | all firmware builds and the native tests | Firmware images (not Ard.Shared, which is source only) |
| `.github` | actionlint, markdownlint, secret scan; the docs drift check is `docs-check.yml`; `deploy-check.yml` validates `deploy/` and starts the compose stack until every service is healthy (also with `compose.observability.yml`, waiting for the metrics in Prometheus and the dashboard in Grafana), restores a configuration backup through the API, and runs `backup.sh`/`restore.sh` and the PowerShell pair against wiped volumes (on changes to `deploy/`) | – |

Releases still follow the [release order](../backlog/README.md#ma3-release-the-net-10-builds-in-order):
Core → Matter → Orchestrator, Elsa, connectors → Node → plugins → UI and Mobile. A release
workflow always validates before it publishes, so a failing test stops the release.

## Contract tests

Added by [I05](../increments/phase-0-1.md#i05-golden-files-and-route-contract-m) (plans
[M7](../plans/m07-contract-integration-tests.md) steps 2–3, [M2](../plans/m02-system-text-json-persistence.md) step 1).

- **Golden files** in [RIoT2.Core/contracts/golden](https://github.com/Revolutionized-IoT2/RIoT2.Core/blob/main/contracts/golden/README.md)
  define the JSON on MQTT, in orchestrator responses and in `StoredObjects`. RIoT2.Tests writes
  and verifies them (`RIOT2_UPDATE_GOLDEN=1` rewrites them); Elsa, the UI and the firmware tests
  read them from a RIoT2.Core clone next to their checkout.
- **REST routes**: every Orchestrator build writes `openapi/riot2-orchestrator.json`, which is
  committed. `verify-generated` fails the Orchestrator CI when a build changes it, and the UI's
  `tests/contracts.test.cjs` fails when the UI calls a route or method the document doesn't have.
- **Contract schema** ([I28](../increments/phase-2.md#i28-narrow-references-and-generated-models-m)): every Core build writes
  [contracts/schemas](https://github.com/Revolutionized-IoT2/RIoT2.Core/blob/main/contracts/schemas/README.md)
  from the contract types (`verify-generated`), RIoT2.Tests validates every golden file against it,
  and the UI build generates its TypeScript models from it (`verify-generated` again).
- A sibling clone is the `main` branch, so a cross-repository change lands producer first (Core or
  Orchestrator), then the consumers. RIoT2.Tests also runs nightly.
- The docs drift check resolves links into other repositories against their `main` branches. Push
  the repository that holds a new file before the hub change that links to it, or the hub's
  `docs-check.yml` fails until the next run.

## End-to-end tests

Added by [I06](../increments/phase-0-1.md#i06-in-process-end-to-end-harness-m) (plan
[M7](../plans/m07-contract-integration-tests.md) step 4). `RIoT2.Tests.Integration`, part of the
RIoT2.Tests CI, runs a broker, the Orchestrator and Node `Program`s, the Devices plugin and a gRPC
workflow stub in one process, without Docker ([RIoT2.Tests README](https://github.com/Revolutionized-IoT2/RIoT2.Tests/blob/main/README.md#end-to-end-tests)).

- It needs a Release build (Debug builds of the Node ignore MQTT configuration); the reusable
  workflow builds and tests in Release.
- A change to the Orchestrator or Node startup, to the Devices plugin, or to a message on the
  main path can fail it. It runs on every RIoT2.Tests push and nightly, so check the nightly run
  after merging such a change.

## Secrets and tokens

- The workflows use `secrets.NUGET_PACKAGE_TOKEN` when it exists and otherwise the job's
  `GITHUB_TOKEN`. Callers pass it with `secrets: inherit` and grant only the permissions they need
  (`packages: write` to publish, `contents: write` for GitHub releases).
- Docker builds receive the feed token only as the BuildKit secret `nuget_token`. The Dockerfile
  passes it to `dotnet restore` through an environment variable of one `RUN`, so no image layer
  stores it. For a local build:

  ```powershell
  $env:NUGET_AUTH_TOKEN = '<token with read:packages>'
  docker build --secret id=nuget_token,env=NUGET_AUTH_TOKEN -t riot2-orchestrator .
  ```

- Workflows use `GITHUB_TOKEN`; the shared personal access token was retired on 2026-10-13
  ([MA5](../backlog/README.md#ma5-require-ci-on-main-and-retire-the-shared-token)). A repository
  needs Read (restore) or Write (publish) in each package's *Manage Actions access*. The
  workflows still prefer a `NUGET_PACKAGE_TOKEN` secret when one exists, so don't add it back.
- A NuGet push that fails with `403 Forbidden` means the token can't write that package: the
  repository has no Write access in the package's *Manage Actions access*, or a
  `NUGET_PACKAGE_TOKEN` secret was added again with an expired token. A secret that exists
  always wins.

## Image and plugin metadata

- `docker-publish.yml` passes `VERSION` and `IMAGE_TAG`. The Orchestrator and Node images write
  them into `/app/Data/Manifest.json`, which the UI shows. Every image gets the OCI labels
  `version`, `source`, `revision` and `created`, and a pushed image its SBOM and provenance (below).
- `PluginManifest.json` has `name`, `date`, `version`, `installedPackageFilename` and, since I03,
  `coreVersion` (the `RIoT2.Core.Devices` version the plugin was built against). The zip holds the
  plugin's top-level assemblies and native libraries, without the assemblies the node already
  ships (`RIoT2.Core*`, `Microsoft.Extensions.*`, `MQTTnet*`, `Newtonsoft.Json`, `Quartz`). The
  node verifies the zip against the `.sha256` sidecar and checks `coreVersion` before it installs it
  (design [7.2](../design/desired-state-configuration.md) phase 4, Node 1.14.0).
- Since [I29](../increments/phase-2.md#i29-plugin-packaging-s) the plugin's own build writes all
  three: Core's `RIoT2.Core.Devices.Build` packs them on every `dotnet publish` (into `bin/plugin/`,
  or `RIoT2PluginOutputDir`), so a local publish gives the release zip. The manifest `name` is
  `RIoT2PluginName` in the plugin's csproj; the workflow's `name` and `package` inputs override
  it (callers still pass `package`, which names the required check).

## SBOMs and pinned base images

Since [I33](../increments/phase-2.md#i33-supply-chain-s) every release carries an SPDX SBOM:

| Release | SBOM | Made by |
|---|---|---|
| Image (`docker-publish.yml`) | BuildKit SBOM and provenance (`mode=max`) attestations in the image index | `sbom: true`, `provenance` |
| Plugin zip (`plugin-release.yml`) | `<zip>.spdx.json` on the GitHub release: every package in the plugin's `deps.json`, including those the node supplies | syft (`anchore/sbom-action`) on the publish output |
| NuGet package (`nuget-publish.yml`) | `<package>.<version>.spdx.json` on the GitHub release of the tag, which the first package job creates | syft on the build output (`deps.json`) |
| Firmware (`firmware-release.yml`) | `firmware-<env>-<version>.spdx.json`: the PlatformIO platform and the libraries the build resolved | a script in `firmware-validate.yml` (syft can't read PlatformIO) |
| Mobile APK | `RIoT2.Mobile_<version>.apk.spdx.json` | Microsoft sbom-tool on `project.assets.json` (the Android output has no `deps.json`) |

CI builds make the same files as artifacts, except the image attestations, which need a push.
Read an image's SBOM with `docker buildx imagetools inspect <image> --format "{{ json .SBOM }}"`.
With attestations, an image tag names an image index; `docker pull` and compose handle it as before.

Every `FROM` in a Dockerfile is pinned as `<image>:<tag>@sha256:<digest>`. The tag says what it
is; the digest makes the build reproducible. Renovate keeps the digests current.

## Dependency updates

Every repository has a `renovate.json` that extends the shared preset
[build/renovate-preset.json](../../build/renovate-preset.json) (rules in the
[build README](../../build/README.md#renovate)). Renovate runs as the Mend Renovate GitHub app,
which the maintainer installs once ([MA7](../backlog/README.md#ma7-install-the-renovate-app)). On
Monday mornings it opens one grouped pull request per repository for minor and patch updates,
and keeps a Dependency Dashboard issue. Each pull request runs CI and needs the required checks.

## Required checks

Since 2026-10-13 branch protection on `main` (or `master` in Elsa) requires every `ci.yml` job
that runs on a push. The check names are `<caller job> / <reusable job>`, for example
`dotnet / build and test (ubuntu-latest)`, `image / image riot2-orchestrator` and
`secret-scan / gitleaks`. Each check is pinned to the GitHub Actions app, so another app can't
satisfy it. Mobile's `android` job runs only on a schedule or manual run, so it isn't required.

- Administrators may bypass (*Do not allow bypassing* is off), so the maintainer can still push
  to `main` directly; GitHub records the bypass. Force pushes and branch deletion are blocked.
- Branches don't have to be up to date before merging (`strict` is off).
- `RIoT2.Net.RasPi.Devices` and `RIoT2.Tests` are private and have no protection, because the
  Free plan doesn't allow it in private repositories. They still run CI on every push.
- **When a job is renamed or added, update the rule** in *Settings → Branches*, or through
  `PUT /repos/{owner}/{repo}/branches/{branch}/protection`. A required check that no longer runs
  stays "Expected" forever and blocks pull requests.
