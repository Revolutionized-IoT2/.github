# 0014. Device plugin SDK built on RIoT2.Core.Devices

- Status: Accepted
- Date: 2026-10-12
- Applies to: RIoT2.Core (the `RIoT2.Core.Devices*` packages), RIoT2.Net.Node, RIoT2.Net.Devices,
  RIoT2.Net.RasPi.Devices, future plugin repositories, RIoT2.UI (parameter editor)

## Context

[ADR 0005](0005-split-core-packages.md) moves the device base classes and interfaces into
`RIoT2.Core.Devices`, but writing and shipping a plugin needs more than base classes (verified
2026-10-12):

- The Devices release workflow zips a hand-written list of 22 DLLs and writes
  `PluginManifest.json` inline. RasPi.Devices has no release workflow. A forgotten dependency fails
  only at runtime on the node.
- The node finds devices through DI (`GetServices<IDevice>()`) and never reads
  `IDevicePlugin.Devices`. RasPi.Devices fills that list; RIoT2.Net.Devices leaves it empty.
- Parameters are untyped string keys (`GetConfiguration<T>("...")`) that are kept in sync with a
  hand-written template by hand. This caused [backlog item 16](../backlog/open-issues.md).
- 23 of 24 devices use the sync `DeviceBase`. Only `EasyPLC` uses `AsyncDeviceBase`, and `Mqtt`
  and `Web` implement both the sync and async command interfaces.
- Each plugin repository writes its own test fakes. Hardware services (I2C, UART, Bluetooth) live
  inside RasPi.Devices and can't be reused.

## Decision

- `RIoT2.Core.Devices` becomes a complete plugin SDK, released from the RIoT2.Core tag with the
  other Core packages:
  - `RIoT2.Core.Devices`: `PluginBase`, typed device options, an async-first device base.
  - `RIoT2.Core.Devices.Build`: an MSBuild target that produces the plugin zip, the manifest and
    the `.sha256` sidecar from the build output.
  - `RIoT2.Core.Devices.Testing`: a fake host and a conformance test.
  - `RIoT2.Core.Devices.Templates`: `dotnet new riot2-plugin`.
  - Later, only when a second plugin needs it: `RIoT2.Core.Devices.Hardware`.
- The list of assemblies shared between node and plugin is defined once in `RIoT2.Core.Devices`,
  and both the node's `PluginLoadContext` and the packaging target use it.
- Plugins must be packaged by the build target, not by hand-written file lists.
- Every plugin repository must run the conformance test.
- Contract changes are additive: an optional `parameterDefinitions` list on `DeviceConfiguration`.
  Existing parameter keys and stored configurations keep working.

## Consequences

- A new plugin is a template plus devices. Packaging, manifest, sidecar and tests come for free.
- Design 7.2 phase 4 (verified plugin updates) gets its sidecar and `coreVersion` from the build
  target instead of per-repository scripts.
- The UI can render typed parameter editors and mask secrets. This is the `isSecret` seam of
  [design 7.5](../design/security-mode.md).
- More Core packages released in lockstep, and the 24 existing devices migrate gradually.
- Implementation plan: [M12](../plans/m12-device-plugin-sdk.md).

## Alternatives considered

- Leaving plugin authoring to each repository: rejected, because packaging and template drift
  have already caused runtime failures and hidden parameters.
- A separate SDK repository: rejected, because the SDK must ship with the exact Core version the
  node loads.
