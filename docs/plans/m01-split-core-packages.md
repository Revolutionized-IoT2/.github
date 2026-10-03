# M1. Split RIoT2.Core into contract and runtime packages

Applies to: see the problem description. Status: snapshot from the September 2026 platform review. Verify against the code before starting work.
Index and dependencies: [plans/README.md](README.md). Backlog: [open-issues.md](../backlog/open-issues.md).

**Problem.** `RIoT2.Core` (85 files) contains the wire contract (`Models`, `Enums`, `Constants`,
message interfaces) together with an MQTT client (`Utils/MqttClient`), HTTP helpers (`Utils/Web`),
a JSON toolbox (`Utils/Json`, 1,100 lines), the device/plugin SDK (`Abstracts/DeviceBase`,
`IDevice*`), the node runtime (`NodeMqttService`, `NodeConfigurationServiceBase`,
`DeviceSchedulerService`) and orchestrator-only service interfaces (`IOrchestrator*Service`,
`IStoredObjectService`, `IMessageStateService`). Every consumer pulls in MQTTnet, Quartz, Hosting,
Newtonsoft and System.Text.Json, and any change forces a coordinated release. That is why the
versions drifted (0.1.41 vs 0.1.43). Elsa and the Influx connector only need `Report`, `Command`,
`ValueModel`, `NodeOnlineMessage`, `Constants`, `Json` and `MqttClient`. `CodeProviderService`/
`ICodeProviderService` are not used by any repository.

**Target packages** (all `netstandard2.0`, namespaces unchanged):

| Package | Contents | Dependencies |
|---|---|---|
| `RIoT2.Core.Contracts` | `Models` (incl. Matter models), `Enums`, `Constants`, `IMessage`/`IReport`/`ICommand`/`ITemplate`, `ValueModel` | System.Text.Json only |
| `RIoT2.Core.Mqtt` | `MqttClient`, `MqttEventArgs` | Contracts, MQTTnet |
| `RIoT2.Core.Http` | `Web` | Contracts |
| `RIoT2.Core.Devices` (plugin SDK) | `DeviceBase`, `AsyncDeviceBase`, `DeviceServiceBase`, `IDevice*`, `IDevicePlugin`, `ICommandService`/`IReportService` | Contracts, Logging.Abstractions, DI.Abstractions |
| `RIoT2.Core.Node` (node host runtime) | `NodeMqttService`, `NodeConfigurationServiceBase`, `ConfigurationBase`, `DeviceSchedulerService`, `CommandService`, `ReportService`, `DeviceOperationAdapter` | Devices, Mqtt, Http, Quartz, Hosting |
| `RIoT2.Core` (compatibility facade) | `[TypeForwardedTo]` for every moved type | all of the above |

## Steps

1. Delete the unused `CodeProviderService`/`ICodeProviderService` and move the orchestrator-only
   interfaces and `MessageStateService` into the Orchestrator repository. They are only
   referenced there. Keep them forwarded from the facade for one release.
2. Create the new projects in the RIoT2.Core repository and move files without changing
   namespaces. Make `RIoT2.Core` a facade that references all of them and forwards the moved
   types, so existing source and existing plugin binaries keep working unchanged. Pack and publish
   all packages from the same tag, with the same version.
3. Update `RIoT2.Net.Node/PluginLoadContext.cs`. Its `SharedContracts` list contains only
   `typeof(IDevice).Assembly`; it must share every assembly whose name starts with `RIoT2.Core`.
   Otherwise a plugin would load its own copy of Contracts, and `Report`/`IDevice` type identity
   would break. Add a test that loads a plugin compiled against the facade.
4. Move consumers to the narrowest packages: Elsa and Influx to `Contracts` + `Mqtt`, plugins to
   `Devices`, Node to `Node`, Orchestrator to `Contracts` + `Mqtt` + `Http`.
5. With [A2](../architecture/target.md#a2-split-core-into-packages), add the `contractVersion` field and export JSON Schemas from `Contracts`
   (`System.Text.Json.Schema.JsonSchemaExporter`). Generate the UI's TypeScript models from those
   schemas in the UI build, replacing the hand-written files in `RIoT2.UI/src/models`.
6. Remove the facade after one release in which every consumer builds without it.

**Risk.** Binary compatibility of already-downloaded plugins; covered by the forwarding facade and
the plugin-loading test from step 3.

**Done when.** Elsa and Influx no longer reference Quartz or Hosting through Core, plugins reference
only `RIoT2.Core.Devices`, and all consumers use one Core version from a single release tag.
