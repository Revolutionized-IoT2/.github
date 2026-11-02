# M12. Device plugin SDK: as built

Applies to: Core, Node and the plugin repositories. The plan, steps and rationale:
[m12-device-plugin-sdk.md](m12-device-plugin-sdk.md). This file records what each step shipped.

## As built, steps 1–2 (I10)

Released in Core `1.5.0`, Node `1.3.0`, Devices and RasPi.Devices `1.2.0`. Before M1 the types
live in the `RIoT2.Core` package, in existing namespaces:

- `RIoT2.Core.Abstracts.PluginBase`: `Register()` with `AddDevice<T>()`, `AddDevice<T>(factory)`,
  `AddService<TService, TImplementation>()` and `AddService<T>(factory)`. The node adds plugin
  controllers (it always did), so plugins don't call `AddControllers`; no suppression was needed
  in the node, which never reads `Devices`.
- `RIoT2.Core.Plugins`: `PluginHostContract` (`SharedAssemblyPrefixes`, `IsShared`),
  `DeviceTemplates.Create` (the template the node returns, moved from the node so the conformance
  test checks the same code) and `[RequiresHardware(reason)]`. `PluginLoadContext` returns the
  node's copy of a shared assembly whatever version the plugin asks for.
- `RIoT2.Core.Devices.Testing` is a separate package from `RIoT2.Core/Testing/`, released by the
  same tag. `PluginConformance.Verify(pluginType, configureServices)` also checks that the
  assembly has exactly one `IDevicePlugin` type, that no device type is registered twice and that
  a template's refresh schedule is a valid Quartz expression. `[RequiresHardware]` devices are
  initialized (a failure is tolerated, reads up to it are still checked) but not started; that
  covers devices calling remote services too, so the test never reaches the internet.
  `configureServices` replaces services, for example the RasPi transports with inert fakes.
- `PluginTestHost` dispatches like the node (async interfaces first) and captures reports; there is
  no separate fake command service. `DeviceConfigurationBuilder` builds configurations.
- Reads are recorded through the internal `DeviceBase.ParameterRead` hook.

## As built, step 3 (I29)

Released in Core `1.15.0`, Devices and RasPi.Devices `1.3.1`:

- `RIoT2.Core.Devices.Build` (`src/Devices.Build/`) is a .NET Standard 2.0 MSBuild task package
  with no run-time dependencies (`DevelopmentDependency`, the task in `tasks/`). It compiles
  `PluginHostContract.cs` from `RIoT2.Core.Devices` (internal there), so the zip and the node's
  `PluginLoadContext` use one list. Node-provided assemblies that aren't shared stay in a property,
  `RIoT2PluginExclude`, with the defaults from `plugin-release.yml` (`Microsoft.Extensions.*`,
  `MQTTnet*`, `Newtonsoft.Json`, `Quartz`).
- `RIoT2PluginPack` runs after `Publish` and packs the top-level `.dll` and `.so` files of
  `ResolvedFileToPublish` (not whatever else is in the publish folder). `coreVersion` is the
  resolved `RIoT2.Core.Devices` package version, else the `RIoT2.Core` facade's, else the assembly
  version of a project reference, else `RIoT2PluginCoreVersion`. The sidecar uses `sha256sum`
  format. Both plugin zips have the same files as before.
- The plugin csproj sets `RIoT2PluginName`; the zip name is `<AssemblyName>_<Version>.zip`.
  `plugin-release.yml` lost its `exclude` input and its packing script; it checks the one zip, the
  sidecar, the manifest version and the absence of `RIoT2.Core*.dll`, and uploads.
- Tests: `PluginPackagerTests` (RIoT2.Tests) and `PackedDevicesPluginInstallsAndLoadsIntoNode`
  (Node), which packs the sibling Devices plugin while the tests build.

## As built, step 4 (I30)

Released in Core `1.16.0`, Node `1.11.0`, Orchestrator `1.14.0`, UI `1.6.0` and Devices `1.4.0`:

- `[DeviceParameter(key, Required, Secret, Default, Description)]` on the properties of an options
  class; `DeviceBase<TOptions>` and `AsyncDeviceBase<TOptions>` (`IDeviceWithOptions`) bind them in
  `Initialize`, before `ConfigureDevice`, through `DeviceOptions.Bind`. An empty value takes
  `Default`, else keeps the property's initial value; a required one without a default, or a value
  that doesn't convert, is a problem. All problems go into one `DeviceOptionsException`, so the
  device is in `Error` with `Invalid device parameters: a; b`. Secret values are never echoed.
- The type comes from the property: `bool` Boolean, integers Integer, `float`/`double`/`decimal`
  Number, anything else (strings, enums) Text. The definition's `default` is the attribute's, or
  the initial value of an optional property.
- `DeviceTemplates.Create` adds `parameterDefinitions` and every missing key (with its default) to
  the template, so migrated devices dropped their hand-written parameter dictionaries and
  placeholder values. The conformance test sees the bound keys as reads.
- C1: keys match case-insensitively, exact match first, in binding and in `GetConfiguration<T>`.
  That is node-side code, so every plugin gets it with Node `1.11.0`.
- The orchestrator strips `parameterDefinitions` when it saves a configuration (stored files and
  hashes are unchanged); the UI reads them from the online node's templates by `classFullName`.
  An offline node or an older plugin leaves free-text fields.
- Migrated: AzureRelay, EasyPLC (port defaults to 10001 instead of 0), FTP (port 21), Mqtt (empty
  user and password are now `null`, an anonymous connection) and Messaging (`smtp_Port` is an
  integer; an invalid one is now an error instead of disabling mail). The other Devices catalog
  devices and all RasPi.Devices devices still read string keys.

## As built, steps 5–6 (I41)

Released in Core `1.23.0`, Node `1.15.0`, Devices `1.7.0` and RasPi.Devices `1.6.0`:

- `AsyncDeviceBase`'s synchronous `StartDevice`, `StopDevice` and `Refresh` are sealed and throw
  `NotSupportedException` instead of blocking on the async members. A virtual `ExecuteCommand`
  that throws satisfies `ICommandDevice`, which `IAsyncCommandDevice` extends, so both plugins
  dropped their `LegacySync` shims; a device keeping synchronous commands overrides it.
  `RefreshAsync` is virtual. Plugin binaries built on older Cores keep their shims and still load.
- `RIoT2.Core.Plugins.DeviceCalls` is how a host calls a device: the async interfaces, or
  `Task.Run` for a legacy synchronous device. `DeviceServiceBase`'s operation queue,
  `CommandService`, `PluginTestHost` and `PluginConformance` use it.
- `DeviceBase` is documented as legacy but not `[Obsolete]`: Timer, Virtual and six RasPi devices
  (AI418ML, CoverDisplay, FONA800, IN830, OC805, RFIDReader) still derive from it. They move before
  Core 2.0 (I45, backlog item 23).
- `RIoT2.Core.Devices.Templates` (`src/Devices.Templates/`) is released from the Core tag.
  `dotnet new riot2-plugin` (options `--CoreVersion`, stamped with the package version when it is
  packed, and `--DisplayName`) creates the plugin with the `Counter` sample
  (`AsyncDeviceBase<TOptions>`, a report and a command), an MSTest project running
  `PluginConformance`, CI and release workflows on the shared workflows, the ADR 0001 documents and
  the platform's `Directory.Build.props` and `.editorconfig`. It has no `nuget.config`: the
  README shows `dotnet nuget add source`, and the shared workflows add the feed.
- Checks: Core CI's `plugin-template` job (`tools/verify-plugin-template.ps1`) installs the packed
  template into a private hive, generates a plugin, tests and publishes it, and checks the zip,
  sidecar and manifest. The Node tests' `PackTemplatePlugin` target does the same with the package
  of the node's Core version; `TemplatePluginInstallsAndLoadsIntoNode` checks `coreVersion`, loads
  the zip, and starts, refreshes, commands and stops the device through `DeviceCalls`.
- Guide: [plugin-authoring.md](../guides/plugin-authoring.md).
