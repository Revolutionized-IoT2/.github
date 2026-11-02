# Writing a device plugin

Applies to: developers adding devices to RIoT2 nodes. Source of truth: the template package
`RIoT2.Core.Devices.Templates` and the SDK in `RIoT2.Core.Devices` (RIoT2.Core `src/Devices/`).
Plan: [M12](../plans/m12-device-plugin-sdk.md). Plugin contract (manifest, `coreVersion`, load context):
[configuration.md](../contracts/configuration.md).

A device plugin is a .NET class library. A node downloads its zip from the URL in the node's
configuration, loads it into its own `AssemblyLoadContext`, resolves the registered devices from DI
and runs the devices you configure in the UI. The catalog plugins `RIoT2.Net.Devices` and
`RIoT2.Net.RasPi.Devices` are built the same way.

## Create a plugin

The RIoT2 packages are on GitHub Packages, which needs a token with `read:packages`, even for
public packages:

```bash
dotnet nuget add source https://nuget.pkg.github.com/Revolutionized-IoT2/index.json --name riot2 \
  --username <github-user> --password <token> --store-password-in-clear-text
dotnet new install RIoT2.Core.Devices.Templates
dotnet new riot2-plugin -n Contoso.Riot2Plugin --DisplayName "Contoso devices"
cd Contoso.Riot2Plugin
dotnet test
dotnet publish Contoso.Riot2Plugin.csproj -c Release
```

| Option | Default | Meaning |
|---|---|---|
| `-n` | the folder name | Project, namespace and zip name |
| `--DisplayName` | `Contoso devices` | `name` in `PluginManifest.json`, shown in the UI |
| `--CoreVersion` | the template package's version | The `RIoT2.Core.Devices*` version the plugin builds on |

The template creates a repository:

| Path | Content |
|---|---|
| `Plugin.cs` | The `PluginBase` that registers the devices |
| `Devices/Counter.cs` | A sample async device with typed options, a report and a command |
| `Tests/` | MSTest: `PluginConformance.Verify` and a test of the sample device |
| `.github/workflows/` | `ci.yml` and `release.yml` on the shared RIoT2 workflows |
| `README.md`, `AGENTS.md`, `CHANGELOG.md` | The per-repository documents of [ADR 0001](../adr/0001-documentation-structure.md) |
| `Directory.Build.props`, `.editorconfig` | The platform's build settings and analyzers |

## Write a device

Derive from `AsyncDeviceBase<TOptions>` and keep every method non-blocking:

| Member | When the node calls it |
|---|---|
| `ConfigureDevice()` | After `Initialize` has bound the options; set up fields, open nothing |
| `StartDeviceAsync(ct)` | When the configuration is applied; connect, subscribe, start timers |
| `StopDeviceAsync(ct)` | Before a new configuration and at shutdown; release everything |
| `RefreshAsync(report, ct)` | On the device's refresh schedule (`report` null: every report) or a refresh request |
| `ExecuteCommandAsync(commandId, value, ct)` | For a command, with `IAsyncCommandDevice`; `value` is JSON |
| `GetConfigurationTemplate()` | With `IDeviceWithConfiguration`; what the UI offers when the device is added |

- **Parameters.** Declare them as properties of an options class with
  `[DeviceParameter(key, Required, Secret, Default, Description)]`. The base class binds them
  before `ConfigureDevice`, puts an invalid configuration into the error state with one message,
  and adds `parameterDefinitions` to the template, so the UI shows typed inputs. Mark passwords and
  tokens `Secret = true`. Read them through `Options`.
- **Reports.** Send a value with `SendReport(this, new Report { Id = template.Id, … })`, where the
  template comes from `ReportTemplates`. Values are `ValueModel`s; keep the report's `Type` and
  `Model` in the template consistent with what you send.
- **Commands.** Look the command up in `CommandTemplates` by `commandId`, and throw for an unknown
  one or a value that doesn't parse: the node reports the command as failed.
- **Errors.** An exception from `StartDeviceAsync`, `StopDeviceAsync` or `RefreshAsync` puts the
  device into `Error` with the message. A cancelled token means the node is applying a new
  configuration or stopping: return promptly.
- **Never block.** The synchronous `IDevice` members of `AsyncDeviceBase` throw
  `NotSupportedException` since Core 1.23.0; the node calls the async ones. Use async I/O, or run a
  blocking driver call with `Task.Run`.
- **Hardware and remote services.** Mark a device that needs either with
  `[RequiresHardware("reason")]`: the conformance test then initializes it but doesn't start it.
- **Shared services.** Register them in `Plugin.Register()` with `AddService<TService, TImplementation>()`.
  Devices get an `ILogger` through their constructor. The assemblies the node shares with plugins
  are listed in `PluginHostContract.SharedAssemblyPrefixes`.

`DeviceBase` (synchronous `StartDevice`, `StopDevice`, `Refresh` and `ICommandDevice`) still works
and is the legacy base class: the node runs its methods on the thread pool. It is removed in Core 2.0
([I45](../increments/phase-3-4.md#i45-core-20-remove-compatibility-layers-m)).

## Test

`PluginConformance.Verify(typeof(Plugin))` (package `RIoT2.Core.Devices.Testing`) loads the plugin
like the node, and checks that every device resolves, has a template with a matching
`ClassFullName` and a valid refresh schedule, reads no parameter missing from its template, and
starts and stops. `PluginTestHost` runs devices and captures their reports; `DeviceCalls` calls a
device the way the node does:

```csharp
await DeviceCalls.StartAsync(device, ct);
await DeviceCalls.ExecuteCommandAsync(device, commandId, "5", ct);
await DeviceCalls.RefreshAsync(device, device.Id, device.Id, ct); // every report; a report id refreshes one
```

## Pack and release

`dotnet publish -c Release` runs the `RIoT2PluginPack` target of `RIoT2.Core.Devices.Build`. It
writes `bin/plugin/<AssemblyName>_<Version>.zip` with the plugin's own DLLs (not the ones the node
provides) and `PluginManifest.json`, and the `<zip>.sha256` sidecar. Pushing a tag `x.y.z` runs
`release.yml`: tests, then a GitHub release with the zip, the sidecar and an SPDX SBOM.

## Install into a node

1. In the UI, open the node's configuration and set the plugin package to the zip's URL. The node
   downloads it, checks the sidecar and installs it at its next start
   ([upgrading.md](upgrading.md#verified-plugin-updates-node-1140)).
2. Add a device of the new type to the node and apply the configuration.

A node installs a plugin only if the manifest's `coreVersion` has the node's Core major and a minor
no newer than the node's. Build on the oldest Core your nodes run: a plugin built on Core 1.23.0
needs Node 1.15.0 or newer. A node's configuration names one plugin package, which replaces the
node's `plugins` folder; plugins copied into that folder by hand load next to each other.

## Rules

- Keep device class names and parameter keys stable: stored configurations refer to
  `ClassFullName` and the keys.
- Don't reference `RIoT2.Core.Node`, `RIoT2.Core.Hosting` or ASP.NET Core from a plugin; the node
  provides `RIoT2.Core*`, `Microsoft.Extensions.*`, `MQTTnet`, `Newtonsoft.Json` and `Quartz`.
- Log through the injected `ILogger` with message templates; never log secret parameter values.
