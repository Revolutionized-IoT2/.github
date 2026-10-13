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
| `node-validate.yml` | Optionally clones sibling repositories (`siblings`), then `npm ci` and the listed npm scripts | UI, Matter Controller UI |
| `firmware-validate.yml` | Clones the four firmware repositories and RIoT2.Core side by side, builds the firmware with PlatformIO, runs the native host tests from `RIoT2.Ard.Shared/tests` with `g++` (including the golden-file test), uploads the images | All `RIoT2.Ard.*` repositories |
| `docker-publish.yml` | BuildKit build of one image for one platform. CI builds without pushing; a release pushes `<tag>` and `latest` (with a suffix such as `-arm64v8`) to GHCR | Orchestrator, Node (amd64 and arm64), Elsa, InfluxDB connector, UI |
| `nuget-publish.yml` | Pack with the tag as version; a release pushes to GitHub Packages. Retries the restore when a package published moments earlier isn't visible yet | Core, Matter (then ControlBridge) |
| `plugin-release.yml` | Publishes a device plugin and packs the node's plugin zip, `PluginManifest.json` and a `.sha256` sidecar; a release attaches them to the GitHub release | Devices, RasPi.Devices |
| `firmware-release.yml` | Validates and builds one firmware project, checks that the tag equals `VERSION`, and attaches `firmware-<env>-<tag>.bin` (or `.hex`), the manifest and `SHA256SUMS` | M5Core2, M5Dial, WiegandI2C |
| `secret-scan.yml` | gitleaks over the whole history, with the repository's `.gitleaks.toml` | Every repository |

The hub's own `ci.yml` runs actionlint on these workflows, markdownlint (`.markdownlint-cli2.jsonc`)
and the secret scan. Change a reusable workflow in a pull request to this repository and check one
caller before merging: every repository uses `@main`.

## Per repository

| Repository | `ci.yml` | `release.yml` on a tag |
|---|---|---|
| Core | build, pack smoke test | NuGet `RIoT2.Core` |
| Matter | build and test on Linux and Windows, Controller UI, pack both packages | NuGet `RIoT2.Matter`, then `RIoT2.Matter.ControlBridge` against it |
| Orchestrator | build; fails if the build changes `openapi/riot2-orchestrator.json` (`verify-generated`); image build | Image |
| Elsa | build, tests with RIoT2.Core cloned for the golden files, image build | Image |
| InfluxDB connector | build, image build (its tests are in RIoT2.Tests) | Image |
| Node | tests with the Devices catalog cloned next to it, amd64 and arm64 image builds | Both images |
| Devices, RasPi.Devices | build, test, plugin zip as an artifact | Plugin zip and `.sha256` on the GitHub release |
| Tests | the cross-repository suite against Core, Orchestrator and InfluxDB connector `main`; also nightly | – |
| UI | `npm test` with RIoT2.Core and the Orchestrator cloned (golden files, OpenAPI route test), `npm run build`, image build | Image |
| Mobile | unit tests; Android APK weekly and on demand | APK and `.sha256` on the GitHub release |
| Ard.Shared, M5Core2, M5Dial, WiegandI2C | all firmware builds and the native tests | Firmware images (not Ard.Shared, which is source only) |
| `.github` | actionlint, markdownlint, secret scan; the docs drift check is `docs-check.yml` | – |

Releases still follow the [release order](../backlog/README.md#ma3-release-the-net-10-builds-in-order):
Core → Matter → Orchestrator, Elsa, InfluxDB connector → Node → plugins → UI and Mobile. A release
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
- A sibling clone is the `main` branch, so a cross-repository change lands producer first (Core or
  Orchestrator), then the consumers. RIoT2.Tests also runs nightly.

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

- To retire the shared personal access token (maintainer action
  [MA5](../backlog/README.md#ma5-require-ci-on-main-and-retire-the-shared-token)), give each
  repository access to the packages it reads and writes, then delete `NUGET_PACKAGE_TOKEN`.
  The workflows fall back to `GITHUB_TOKEN` without a change.
- A NuGet push that fails with `403 Forbidden` means the token can't write that package: the
  secret's token expired, or `GITHUB_TOKEN` is used and the repository has no Write access in the
  package's *Manage Actions access*. A secret that exists always wins, even when its token is
  expired.

## Image and plugin metadata

- `docker-publish.yml` passes `VERSION` and `IMAGE_TAG`. The Orchestrator and Node images write
  them into `/app/Data/Manifest.json`, which the UI shows. Every image gets the OCI labels
  `version`, `source`, `revision` and `created`. SBOM and provenance attestations come with I33.
- `PluginManifest.json` has `name`, `date`, `version`, `installedPackageFilename` and, since I03,
  `coreVersion` (the `RIoT2.Core` version the plugin was built against). The zip holds the
  plugin's top-level assemblies and native libraries, without the assemblies the node already
  ships (`RIoT2.Core*`, `Microsoft.Extensions.*`, `MQTTnet*`, `Newtonsoft.Json`, `Quartz`). The
  `.sha256` sidecar is for the verified install in design
  [7.2](../design/desired-state-configuration.md) phase 4.

## Required checks

Branch protection on `main` (or `master` in Elsa) requires the `ci.yml` jobs. The check names
are `<caller job> / <reusable job>`, for example `dotnet / build and test (ubuntu-latest)`,
`image / image riot2-orchestrator` and `secret-scan / gitleaks`. Setting them is part of
[MA5](../backlog/README.md#ma5-require-ci-on-main-and-retire-the-shared-token).
