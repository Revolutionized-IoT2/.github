# M8. .NET 10 migration and shared engineering practices (A10)

Applies to: see the problem description. Status: steps 1–8 and 11 done in code on 2026-10-03; the
releases are maintainer action [MA3](../backlog/README.md#ma3-release-the-net-10-builds-in-order).
Steps 9–10 are open. The problem table is the September 2026 snapshot.
Index and dependencies: [plans/README.md](README.md). Backlog: [open-issues.md](../backlog/open-issues.md).

**Problem.** .NET 8 and .NET 9 both reach end of support on **10 November 2026**, about six weeks
from this review. After that date there are no security fixes for the runtime in any container
image. Current state:

| Repository | Projects | Today | Target | Notes |
|---|---|---|---|---|
| RIoT2.Core | library | `netstandard2.0`, Microsoft.Extensions 9.0.0, System.Text.Json 9.0.0 | stays `netstandard2.0`, packages 10.0.x | Microsoft.Extensions 10 packages still ship `netstandard2.0` assets |
| RIoT2.Connector.InfluxDB | app | `net8.0`, image `aspnet:8.0-alpine` | `net10.0`, `aspnet:10.0-alpine` | Remove the unused `Microsoft.VisualStudio.Azure.Containers.Tools.Targets` reference |
| RIoT2.Net.Orchestrator | app | `net9.0`, `aspnet:9.0-alpine` / `sdk:9.0` | `net10.0`, `aspnet:10.0-alpine` / `sdk:10.0` | Keep the glibc SDK image for `protoc`. Update Grpc.Net.Client/Grpc.Tools/Google.Protobuf together. |
| RIoT2.Net.Node | app | `net9.0`, `aspnet:9.0-alpine` and `aspnet:9.0-bookworm-slim-arm64v8` | `net10.0` | .NET 10 images use Ubuntu 24.04 as the default Linux distribution, so pick the matching arm64 tag from the current tag list. Serilog.AspNetCore 9 → 10, Microsoft.Extensions.Logging 9.0.18 → 10. |
| RIoT2.Net.Devices, RIoT2.Net.RasPi.Devices | plugins | `net9.0` | `net10.0` | **After** the node: a `net10.0` plugin can't load into a `net9.0` node, but a `net9.0` plugin loads into a `net10.0` node. |
| RIoT2.Matter (+ ControlBridge, Controller, OnOffSample, Tests) | libraries, apps | `net9.0` | `net10.0` | **After** the orchestrator, which consumes the packages. The Controller UI (Vite) is unaffected. |
| RIoT2.Elsa | apps | `net10.0`, Elsa 3.7.1 | unchanged | Already done |
| RIoT2.Mobile | MAUI app | `net9.0-android;net9.0-windows10.0.19041.0`, `global.json` 9.0.100 | `net10.0-*`, `global.json` 10.0.100, MAUI 10 workload | Check that CommunityToolkit.Maui (11.0.0) and Plugin.Firebase.CloudMessaging (4.0.0) have `net10.0` versions **before** starting; they are the main risk. Raise the Android target API level to the current Play Store requirement. |
| RIoT2.Tests and the per-repo test projects | tests | `net9.0`, MSTest.Sdk 3.6.1; Matter uses xUnit 2.9 | `net10.0`, current MSTest.Sdk | xUnit stays on 2.x for now |
| RIoT2.UI | Node build image | `node:22` | `node:24` (active LTS) | Not a .NET change, but done in the same pass |

A separate portability bug is fixed in the same pass: `RIoT2.Mobile/Directory.Build.props` hard-codes
`BaseIntermediateOutputPath=C:\o\…` and `BaseOutputPath=C:\b\…`, which breaks the build on any
other machine and in Linux CI. Replace them with paths relative to `$(MSBuildThisFileDirectory)`,
and keep the `DefaultItemExcludes` fix.

## Steps (TFM migration, roadmap phase 1 because of the deadline)

1. **Build templates.** Add `build/Directory.Build.props`, `build/Directory.Packages.props.template` and
   `build/.editorconfig` to this `.github` repository, and copy them into each .NET repository. Every
   repository is its own solution, so an MSBuild SDK package isn't worth the overhead. The props file
   sets:
   - `LangVersion=latest`, `ImplicitUsings`, `Deterministic` and `ContinuousIntegrationBuild` in CI;
   - `EnableNETAnalyzers` with `AnalysisLevel=latest-recommended`;
   - `TreatWarningsAsErrors` only when `CI=true`, so local builds aren't blocked.

   All repositories built with 0 warnings in September 2026 ([review](../reviews/2026-09-platform-review.md#1-scope-and-verification)), so this is safe with the default rule
   set. Any new analyzer findings are either fixed or suppressed in `.editorconfig` with a reason.
2. **Central package management.** Add `Directory.Packages.props` to each repository with the
   versions from the inventory above. Align the duplicates found in the review: Serilog.AspNetCore 9/10,
   Serilog.Sinks.File 6/7, Microsoft.Extensions.Logging 9.0.0/9.0.18, and the three RIoT2.Core versions
   ([maintainer action MA2](../backlog/README.md#ma2-cut-a-core-release-and-align-all-consumers)).
3. Bump Core's Microsoft.Extensions and System.Text.Json packages to 10.0.x and release Core.
4. Move Influx and the Orchestrator to `net10.0` and the 10.0 images, and release them.
5. Move the Node (both Dockerfiles) to `net10.0` and release it. Then move Devices and RasPi.Devices
   and release them. The profile README and the upgrade notes say "update the node image before
   installing the new plugin zip".
6. Move Matter to `net10.0` and release the packages. Then bump them in the Orchestrator.
7. Move Mobile to MAUI 10, if the dependency check in the table passed. Otherwise keep Mobile on
   `net9.0` temporarily: it is a client app, not a server, so the end-of-support risk is lower. Record
   that as an exception.
8. Point CI `setup-dotnet` at `10.0.x` everywhere ([M9](m09-ci-cd.md)) and update the test projects.

## Steps (practices, roadmap phase 2)

9. **Nullable reference types**, one project at a time:
   - Matter, Mobile and Elsa already have them enabled.
   - For Core (`netstandard2.0`), add the `Nullable` attributes polyfill package, annotate
     `Contracts` first ([M1](m01-split-core-packages.md)), and turn on `<Nullable>enable</Nullable>` once the warnings are fixed.
   - Orchestrator, Node, the plugins, Influx and Tests start with `<Nullable>annotations</Nullable>`,
     then move to `enable` per project.
   - Changed files get `#nullable enable` from now on.
10. **Threading analyzers** (`Microsoft.VisualStudio.Threading.Analyzers`) as warnings: VSTHRD002
    (synchronous wait), VSTHRD100 (`async void`) and VSTHRD110 (unobserved task). These keep [M11](m11-async-cleanup.md) from
    regressing.
11. SourceLink and symbol packages for the NuGet packages (Core, Matter, SDK).

## Risk

- Plugin load order (step 5) is the main operational risk. It is covered by the release order and
  a plugin-loading test in the Node test project, which loads a plugin built against the old TFM.
- MAUI dependencies (step 7) may force the temporary exception for Mobile.

## Done when

- No `net8.0`/`net9.0` targets remain (Mobile only by recorded exception), and all images use 10.0 tags.
- CI builds with `TreatWarningsAsErrors`.
- Every repository uses central package management with no duplicate versions for shared packages.

## Implementation notes (2026-10-03)

Decisions taken while implementing steps 1–8 and 11, where the code differs from the text above:

- **Templates** are in [build/](../../build/README.md). `Directory.Build.props` and `.editorconfig`
  are identical everywhere. Repository-specific MSBuild settings go in `Directory.Build.repo.props`
  (only Mobile has one, for its output paths).
- **Analyzer findings.** `latest-recommended` raised existing findings in every repository. They
  are lowered to `suggestion` in `.editorconfig`, grouped with a reason. Two were fixed instead:
  a logging template mismatch in Core's `DeviceBase` (CA2017), and the Matter SHA-1 key
  identifier (CA5350) got a justified `SuppressMessage`, because the spec requires it.
- **NuGet warnings.** NU1507 (no package source mapping) is suppressed until M9 owns the feeds.
  Audit warnings NU1901–NU1904 are not errors in CI.
- **SDK drift.** CI installs the newest 10.0.x SDK. SDK 10.0.4xx added CA1873 and stricter nullable
  analysis to the 10.0 level, which broke the first Matter CI run. Pinning `AnalysisLevel` doesn't
  help within a major version. CA1873 is lowered with the other logging rules, and the two real
  findings (a null Level Control read in Matter, a blocking `EndOfStream` in Hue) were fixed.
  Pinning the SDK band (`global.json` plus `setup-dotnet` `global-json-file`) belongs to M9.
- **Versions.** Core `0.1.45` (10.0.12 packages, includes the `0.1.44` fixes) and Matter `0.1.15`
  are the new releases. All Microsoft 10.0 servicing packages use 10.0.12. The gRPC family moved
  to 2.84.0 in both the Orchestrator and Elsa. The Node's `Microsoft.Extensions.Logging`
  reference was removed instead of bumped: the .NET 10 framework provides it (NU1510).
- **Mobile needs no exception.** CommunityToolkit.Maui 15 supports .NET 10.
  Plugin.Firebase.CloudMessaging has no `net10.0` build yet, but its `net9.0-android` assets work
  from `net10.0-android`. The Android target API is 36. Three warnings in Android-only code
  were real defects and were fixed.
- **Tests** use MSTest.Sdk 4.4.1. MSTest 4 removed `Assert.ThrowsException`; the tests use
  `Assert.ThrowsExactly`, which has the same exact-type semantics.
- **Plugin-loading test.** `RIoT2.Net.Node/Tests/LegacyPlugin` is a fixture plugin that stays one
  target framework behind the node. `PluginCompatibilityTests` loads it the way `Program.cs` does.
- **Images.** Each Dockerfile copies `Directory.Build.props` and `Directory.Packages.props` before
  `dotnet restore`. The ARM64 node runtime is `aspnet:10.0-noble-arm64v8`.
- **Step 11.** The SDK's built-in SourceLink, plus `DebugType=embedded` in the packed libraries,
  because GitHub Packages has no symbol server.
- **Steps 9–10 stay open.** Enabling nullable annotations in the Orchestrator or Node makes
  ASP.NET Core MVC treat non-nullable request properties as implicitly `[Required]`. That is an
  API behaviour change, so it needs a per-project review. M11 step 4 turns on the threading
  analyzers.
