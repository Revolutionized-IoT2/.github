# M8. .NET 10 migration and shared engineering practices (A10)

Applies to: see the problem description. Status: snapshot from the September 2026 platform review. Verify against the code before starting work.
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
