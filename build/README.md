# Shared .NET build templates

Applies to: every RIoT2 .NET repository (Core, Connector.InfluxDB, Net.Orchestrator, Net.Node,
Net.Devices, Net.RasPi.Devices, Matter, Elsa, Mobile, Tests). Introduced by plan
[M8](../docs/plans/m08-dotnet10-migration.md) steps 1–2.

Every repository is its own solution, so these files are copied rather than shipped as an MSBuild
SDK package.

| File | Copy to the repository root as | Rule |
|---|---|---|
| [Directory.Build.props](Directory.Build.props) | `Directory.Build.props` | Identical in every repository. Repository-specific settings go in `Directory.Build.repo.props`, which it imports when present (Mobile uses it for its output paths). |
| [.editorconfig](.editorconfig) | `.editorconfig` | Identical in every repository. |
| [Directory.Packages.props.template](Directory.Packages.props.template) | `Directory.Packages.props` | Keep only the shared versions the repository uses, unchanged, and add its own packages in a separate group. |

## What the props file does

- `LangVersion=latest`, `ImplicitUsings`, `Deterministic`.
- `EnableNETAnalyzers` with `AnalysisLevel=latest-recommended`. Rules that already had findings
  when this was switched on are lowered to `suggestion` in `.editorconfig`, each with a reason.
  To tighten one, fix its findings everywhere and delete its line.
- With `CI=true` (set by GitHub Actions): `ContinuousIntegrationBuild` and
  `TreatWarningsAsErrors`. Local builds are never blocked. NuGet vulnerability advisories
  (NU1901–NU1904) stay warnings so a new advisory can't break an unrelated build.
- NU1507 (several feeds without package source mapping) is suppressed until the reusable CI
  workflows of [M9](../docs/plans/m09-ci-cd.md) own the feed configuration.
- SourceLink: `PublishRepositoryUrl` and `EmbedUntrackedSources`. The .NET SDK adds SourceLink
  for GitHub repositories. Packed libraries (Core, Matter, ControlBridge) set
  `DebugType=embedded` in their project file, because GitHub Packages has no symbol server.

## Rules

- You must change the template here first, then copy it to every repository in the same pass.
- A repository must not set a different version for a package in the shared block.
- Test projects use `MSTest.Sdk/4.4.1` in the project `Sdk` attribute (it can't be centrally
  managed). Matter's tests stay on xUnit 2.x.
- Dockerfiles must copy `Directory.Build.props` and `Directory.Packages.props` next to the
  project file before `dotnet restore`.
- To check a repository the way CI does, build it with warnings as errors:

```powershell
dotnet build .\RIoT2.Net.Node\Tests\RIoT2.Net.Node.Tests.csproj -c Release -p:CI=true
```
