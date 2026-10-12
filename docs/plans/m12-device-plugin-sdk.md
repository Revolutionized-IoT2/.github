# M12. Device plugin SDK

Applies to: RIoT2.Core (`RIoT2.Core.Devices*` packages), RIoT2.Net.Node, RIoT2.Net.Devices,
RIoT2.Net.RasPi.Devices, RIoT2.UI. Status: accepted 2026-10-12 ([ADR 0014](../adr/0014-device-plugin-sdk.md)), not implemented.
Verify against the code before starting work.
Index and dependencies: [plans/README.md](README.md). Backlog: [item 23](../backlog/open-issues.md).

**Problem.** [M1](m01-split-core-packages.md) gives plugins their own package, `RIoT2.Core.Devices`,
but writing, testing and shipping a plugin still has no support beyond the base classes:

- **Packaging is manual.** `RIoT2.Net.Devices/.github/workflows/main.yml` zips a hand-written
  list of 22 DLLs and writes `PluginManifest.json` with a heredoc. `RIoT2.Net.RasPi.Devices` has
  no release workflow. A forgotten dependency only fails when the node loads the plugin.
- **`IDevicePlugin.Devices` does nothing.** `RIoT2.Net.Node/Program.cs` resolves devices with
  `GetServices<IDevice>()` and never reads the list. `RIoT2.Net.RasPi.Devices/Plugin.cs` fills it;
  `RIoT2.Net.Devices/Plugin.cs` leaves it empty.
- **Parameters are untyped.** Devices read `DeviceParameters` (`Dictionary<string, string>`)
  through `GetConfiguration<T>("key")`, and separately hand-write a template with placeholder
  strings. Nothing says which parameters are required, secret or numeric, and the two drift apart
  ([backlog item 16](../backlog/open-issues.md)).
- **Two lifecycles.** 23 of 24 devices derive from the sync `DeviceBase`. `AsyncDeviceBase`
  (used only by `EasyPLC`) wraps its async methods in blocking calls, and `Mqtt`/`Web` implement
  both `ICommandDevice` and `IAsyncCommandDevice`.
- **No shared test support.** Each plugin test project builds its own fakes. The node's
  `NodeIntegrationHarness` isn't reusable from plugin repositories.
- **Shared assembly list in one place only.** `RIoT2.Net.Node/PluginLoadContext.cs` hard-codes
  which assemblies plugins share with the host. Packaging has to exclude exactly those, but has no
  way to know them.

## Steps

Each step ships on its own and keeps existing plugins and stored configurations working.

1. **Host contract and `PluginBase` (S).**
   - Add `PluginHostContract.SharedAssemblyPrefixes` to `RIoT2.Core.Devices` (today:
     `RIoT2.Core`, `Microsoft.Extensions.DependencyInjection.Abstractions`,
     `Microsoft.Extensions.Logging.Abstractions`; after M1 every `RIoT2.Core*`). Make
     `PluginLoadContext` use it.
   - Add an abstract `PluginBase : IDevicePlugin` with `AddDevice<T>()` and `AddService<TService,
     TImplementation>()`. Controllers are added once, by the base class.
   - Mark `IDevicePlugin.Devices` as `[Obsolete]` with a message that the host uses DI. Suppress the
     warning in the node only. Remove the member in the next major release.
   - Move both plugins to `PluginBase`.
2. **Testing kit, `RIoT2.Core.Devices.Testing` (M).**
   - A `PluginTestHost` that loads a plugin the way the node does (`Initialize(services)`, then
     `GetServices<IDevice>()`), with a capturing report sink, a fake command service and a
     `DeviceConfigurationBuilder`.
   - `PluginConformance.Verify(typeof(Plugin))` asserts that:
     - every device resolves;
     - every device returns a configuration template whose `ClassFullName` matches;
     - every parameter key the device reads during `Initialize` is in its template. Reads are
       recorded through an internal hook in `DeviceBase.GetConfiguration<T>`, visible to the
       testing package only.
   - Devices that need hardware opt out of the start/stop check with `[RequiresHardware]`.
   - This replaces the per-repository reflection test planned in [M6](m06-plugin-configuration-discovery.md) step 2. Do M6 step 1
     (the missing templates) first, so the test passes.
3. **Packaging, `RIoT2.Core.Devices.Build` (S).**
   - A `buildTransitive` MSBuild target, `RIoT2PluginPack`, that runs after `Publish`. It takes the
     publish output, removes framework assemblies and everything in `SharedAssemblyPrefixes`, and
     writes `PluginManifest.json` (`name`, `version`, `date`, `installedPackageFilename`,
     `coreVersion`), the zip and a `<zip>.sha256` sidecar.
   - The zip's own hash can't be stored inside the zip. The node records it in its installed
     manifest at install time ([design 7.2](../design/desired-state-configuration.md)).
   - Add a reusable `plugin-release.yml` to this repository's workflows ([M9](m09-ci-cd.md)). Both
     plugin repositories call it, which gives RasPi.Devices its first release workflow.
   - Test: pack the Devices plugin, extract it, and load it with the node's `PluginLoadContext` in
     `PluginCompatibilityTests`.
4. **Typed device options (M, after M1).**
   - A device declares an options class:

     ```csharp
     public sealed class MessagingOptions
     {
         [DeviceParameter("smtp_Server", Required = true)] public string SmtpServer { get; set; }
         [DeviceParameter("smtp_Port", Default = "587")] public int SmtpPort { get; set; }
         [DeviceParameter("smtp_Password", Secret = true)] public string SmtpPassword { get; set; }
     }
     public class Messaging : DeviceBase<MessagingOptions>, ICommandDevice { … }
     ```

   - `DeviceBase<TOptions>` binds and validates `DeviceParameters` in `Initialize`. Missing or
     invalid values put the device into `DeviceState.Error` with one message that lists every
     problem. The device reads `Options` instead of string keys.
   - The base class builds the parameter part of `GetConfigurationTemplate()` from the attributes.
     Keys keep their current spelling, so stored configurations load unchanged.
   - Contract (additive): `DeviceConfiguration.parameterDefinitions`, a list of
     `{ key, type, required, secret, default, description }`. Ship it in the additive Core contract
     release of roadmap phase 2 if it's ready, otherwise in a later additive release. Old UIs
     ignore it.
   - UI: render typed inputs and mask `secret` values (the `isSecret` seam of
     [design 7.5](../design/security-mode.md)), falling back to today's free-text fields when
     `parameterDefinitions` is missing.
   - Migrate devices one pull request at a time. The conformance test from step 2 checks each one.
5. **Async-first lifecycle (M, after [M11](m11-async-cleanup.md)).**
   - Once the node host calls devices asynchronously (M11), `AsyncDeviceBase` becomes the default
     base class and stops blocking on its own methods. Commands go through `IAsyncCommandDevice`
     only; the host adapts the sync interface for devices that haven't migrated.
   - `DeviceBase` stays for one major release and is documented as legacy. It isn't marked
     `[Obsolete]` until every catalog device has migrated, because warnings are errors in CI.
6. **Plugin template, `RIoT2.Core.Devices.Templates` (S, after steps 1–4).** `dotnet new
   riot2-plugin` creates:
   - a plugin project using `PluginBase`, the build package and one sample device with options;
   - a test project running `PluginConformance`;
   - a release workflow calling `plugin-release.yml`;
   - the per-repository document set from [ADR 0001](../adr/0001-documentation-structure.md).
7. **Hardware package, `RIoT2.Core.Devices.Hardware` (M, only on demand).** When a second plugin
   needs I2C, UART or Bluetooth, move `II2CService`, `IUartService`, `IBluetoothService` and their
   Linux implementations out of `RIoT2.Net.RasPi.Devices`, and leave forwarding registrations in
   that plugin for one release.

Also add a plugin authoring guide to the documentation when step 6 ships, and update
[contracts/configuration.md](../contracts/configuration.md) with `parameterDefinitions` in the same
change as step 4.

**Dependencies.** Steps 1–3 need nothing new: before M1 they reference the `RIoT2.Core` package.
Step 3's workflow uses M9. Step 3 is needed by design 7.2 phase 4. Step 4 needs M1, and step 5
needs M11.

**Effort.** L in total. Steps 1, 3 and 6 are S; steps 2, 4, 5 and 7 are M.

**Done when.**

- Both plugin repositories use `PluginBase`, the build target and the shared release workflow, and
  run the conformance test.
- No catalog device reads a parameter through a string key.
- `IDevicePlugin.Devices` is gone.
- `dotnet new riot2-plugin` produces a plugin that builds, packs, passes conformance and loads in
  the node.
