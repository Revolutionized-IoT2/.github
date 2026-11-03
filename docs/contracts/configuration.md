# Node configuration, templates, persistence and plugins

Applies to: Orchestrator (stores and serves configuration), Node, firmware, device plugins, UI
(edits configuration).

Source of truth:

| Topic | Code |
|---|---|
| Models | `RIoT2.Core/src/Contracts/Models/NodeDeviceConfiguration.cs`, `DeviceConfiguration.cs`, `ReportTemplate.cs`, `CommandTemplate.cs`, `Models/Matter/*` |
| Firmware model | `RIoT2.Ard.Shared/RIoT2Shared/include/riot2/DeviceConfiguration.h`, `src/OrchestratorClient.cpp` |
| Persistence | `RIoT2.Net.Orchestrator/Services/Persistence/FileObjectStore.cs` |
| Plugin loading | `RIoT2.Net.Node/Program.cs`, `RIoT2.Core/src/Node/Abstracts/NodeConfigurationServiceBase.cs` |
| Desired state | `RIoT2.Core/src/Contracts/Utils/ConfigurationHash.cs`, `src/Node/Services/NodeConfigurationStatus.cs`, `src/Node/Abstracts/NodeConfigurationServiceBase.cs`, `RIoT2.Net.Node/Services/DeviceConfigurationApplier.cs`, `RIoT2.Net.Orchestrator/Services/OrchestratorConfigurationService.cs`, `OnlineNodeService.cs` |

## How configuration flows

1. The user creates a node in the UI with the same id as the node's `RIOT2_NODE_ID` (or the
   firmware's provisioned id). The UI adds devices, picked from the templates that the online node
   reports (`GET /api/nodes/{id}/device/templates`). The UI saves with
   `POST /api/nodes/configuration`.
2. The orchestrator persists the configuration with a new revision and hash. After the save, and
   whenever the node comes online, it publishes `riot2/node/{id}/configuration` with them
   ([mqtt-delivery.md](mqtt-delivery.md#lifecycle)).
3. A .NET node that runs that hash, with every device running, only publishes its status
   ([Desired state](#desired-state)). Otherwise the node fetches
   `GET {apiBaseUrl}/api/nodes/{id}/configuration` and restarts only the devices whose entry was
   added, changed or removed, plus configured devices that aren't running (Core 1.1.0):
   - Their old work is cancelled and awaited, and they are stopped.
   - New and changed devices are initialized and started. Removed devices stay stopped.
4. If the configuration contains a `pluginPackageUrl` whose file name differs from the installed
   package, the .NET Node downloads the package. It is installed on the next start
   ([Plugins](#plugins-net-node)).

## Desired state

From Orchestrator 1.5.0 and Node 1.5.0 (Core 1.8.0; [design 7.2](../design/desired-state-configuration.md) phases 2–3):

- **Revision and hash.** On every save the orchestrator stamps the configuration: `hash` on each
  `deviceConfigurations[]` entry and on the document is the lowercase hex SHA-256 of
  `Json.Serialize` of it without its own `revision` and `hash` (`ConfigurationHash.Stamp`).
  `revision` counts content changes: saving the same content keeps it. Configurations saved before
  1.5.0 get revision 1 and their hash when loaded. `GET /api/nodes/{id}/configuration` sends the
  hash as `ETag` and answers a matching `If-None-Match` with `304`.
- **The node** compares the command's `hash` with the one it applied. A command for the applied
  configuration, with every device running, or for the one being applied, needs no work. Any other
  command fetches with `If-None-Match` for the configuration the node holds; a `304` applies that
  one again, which starts devices that aren't running. A command without a hash (an orchestrator before 1.5.0) is always
  fetched, and the device diff still restarts nothing that didn't change.
- **Status.** The node publishes `NodeStatusMessage` retained on `riot2/node/{id}/status`
  ([mqtt-topics.md](mqtt-topics.md#nodestatusmessage-riot2coresrccontractsmodelsnodestatusmessagecs)): on every
  connect, before its presence, and on every change. `failedDevices` lists configured devices that
  aren't running, including those whose class no loaded plugin provides.
- **Failures.** When fetching or reading the configuration fails, the node keeps the previous one
  and reports `failed`. The orchestrator logs it; the next save or presence tries again.
- **Saved configuration.** After applying, the node saves the configuration to
  `Data/configuration.applied.json` (`/app/Data` in the image, a volume), and on start it applies
  that file before it connects. With the orchestrator down, the node still runs its devices.
- **Sync state.** `GET /api/nodes` and `GET /api/v2/nodes/sync` report per node `desiredRevision`,
  `appliedRevision`, `configurationState`, `lastError`, `failedDevices` and `syncState`: `inSync`
  (the status is `applied` with the saved hash), `pending` (applying, another hash, or no status
  yet), `failed`, or `legacy` (online without `desired-state/1`). The UI shows it per node and
  re-applies with `POST /api/v2/nodes/{id}/configuration/apply` (I36). A deleted node's retained
  status is cleared.
- The configuration command goes out on every presence: a retained status can be older than its node.
- **Firmware** (0.5.0, [design 7.2](../design/desired-state-configuration.md) phase 5) differs: it
  keeps no saved configuration (after a restart it reports `applying` and fetches), the applied
  hash needs no work even with failed devices (classes the build lacks), and its status is compact
  ([mqtt-topics.md](mqtt-topics.md#nodestatusmessage-riot2coresrccontractsmodelsnodestatusmessagecs)).

**Debug builds of the .NET Node** ignore `configuration` messages and load
`Data/local.configuration.json` instead (`#if DEBUG` in the node's `ConfigurationService.cs`,
`MqttBackgroundService.cs` and Core's `NodeMqttService.cs`). That file can hold real credentials,
so a Debug build starts real devices. Use Release builds for integration tests and screenshots;
the end-to-end tests report inconclusive in a Debug build.

## Schema (`GET /api/nodes/{id}/configuration`)

Serialized by the orchestrator with `Json.Serialize` (camelCase, enums as numbers; System.Text.Json
with `RIoT2JsonOptions` since Core 1.11.0, byte for byte what Newtonsoft wrote before):

```json
{
  "id": "F811B5A0-E978-45BB-ADD3-584655DF21BF",
  "name": "Garage node",
  "revision": 3,
  "hash": "9f2c?",
  "pluginPackageUrl": "https://<host>/<plugin-package>.zip",
  "deviceConfigurations": [
    {
      "id": "web-1",
      "name": "Webhooks",
      "classFullName": "RIoT2.Net.Devices.Catalog.Web",
      "deviceParameters": { "someKey": "value" },
      "refreshSchedule": "0 0/5 * * * ?",
      "reportTemplates": [
        { "id": "door-open", "name": "Door open", "type": 0, "address": "door",
          "parameters": { "unit": "" }, "filters": [], "maintainHistory": true, "model": false }
      ],
      "commandTemplates": [
        { "id": "door-lock", "name": "Lock door", "type": 0, "address": "lock", "model": true }
      ],
      "matterEndpoints": []
    }
  ]
}
```

| Field | Meaning |
|---|---|
| `classFullName` | Full .NET type name of the device class in a loaded plugin, or the firmware view/peripheral class name; how the node finds the implementation. |
| `deviceParameters` | Device settings (`Dictionary<string,string>`), bound to typed options (every catalog device since Core 2.0.0) or read with `GetConfiguration<T>`. Keys match case-insensitively since Core 1.16.0. May contain third-party secrets; never commit them. |
| `parameterDefinitions` | Templates only (Core 1.16.0), omitted when unset: `{ key, type, required, secret, default?, description? }` per parameter; `type` is `0` Text, `1` Number, `2` Integer, `3` Boolean. The orchestrator doesn't store it. |
| `refreshSchedule` | Optional Quartz cron expression for refreshable devices. Validate with `POST /api/nodes/validatecron`. |
| `reportTemplates[].id` | Globally unique. Becomes `Report.id`. The orchestrator ignores reports without a matching template. |
| `reportTemplates[].type`, `commandTemplates[].type` | `ValueType`: `0` Boolean, `1` Text, `2` Number, `3` Entity, `4` TextArray |
| `reportTemplates[].address`, `commandTemplates[].address` | Device-specific address, e.g. the Web device's webhook path or the MQTT device's topic. |
| `reportTemplates[].parameters` | Display hints such as `unit` and `precision` |
| `reportTemplates[].filters` | Allowed `Report.filter` values |
| `reportTemplates[].maintainHistory` | The orchestrator keeps history (`/api/dashboard/report/{id}/history`) |
| `model` | Example or default value. `CommandTemplate.GetAsCommand()` uses it as the default command value. |
| `commandTemplates[].id` | Globally unique. The orchestrator maps a `Command.id` to the owning node. |
| `matterEndpoints` | Matter declarations ([`MatterEndpointTemplate`](https://github.com/Revolutionized-IoT2/RIoT2.Core/blob/main/src/Devices/matter-declarations.md)) |

Variables (`Variable`, `VariableTemplate`) are orchestrator-side values. They can be used as
command targets from Elsa (`RIoTOutput`) and are read with `/api/variable/{id}/value`.

### Firmware subset

The firmware parses only `id`, `name`, `revision`, `hash` (firmware 0.5.0) and
`deviceConfigurations[]`, and from each device only:

- `id`, `name`, `classFullName`
- `deviceParameters` (as string pairs)
- `commandTemplates[]`: `id`, `type` (number), `name`, `address`, `model`
- `reportTemplates[]`: `id`, `type` (number), `name`, `address`, `parameters`

It ignores `refreshSchedule`, `matterEndpoints`, `filters` and `maintainHistory`. On-screen views
and Grove peripherals are both entries in `deviceConfigurations`, told apart by `classFullName`.
Responses larger than 32 KiB are rejected. The templates the firmware serves on
`GET /api/device/configuration/templates` have the same fields, with `type` as a number as well
(since RIoT2.Ard firmware 0.2.0; before that it was a string, divergence C2).

## Known divergences

Fixed divergences are removed and their IDs are never reused: C1 (`Json.Serialize` camel-cases
`deviceParameters` keys, but devices read them case-sensitively; since Core 1.16.0 and
[I30](../increments/phase-2.md#i30-typed-device-options-m) keys match case-insensitively) and C2
(firmware read template `type` as a string, fixed in [I13](../increments/phase-0-1.md#i13-firmware-ota-rollback-s)).
None is open.

## Orchestrator persistence (`StoredObjects`)

- Layout: `<content-root>/StoredObjects/<TypeName>/<id>.json`, which in the container is
  `/app/StoredObjects/...`.
- Type names and ids are validated as safe file names (no path traversal). Never build paths
  from raw ids.
- Format: System.Text.Json (`StoredObjectJson`, Orchestrator 1.11.0), the bytes Newtonsoft wrote
  before, without `$type`. Files of legacy types (`Rule`) move to the hidden
  `StoredObjects/.archive/<Type>/` at startup and after a restore; it is not loaded, backed up or
  replaced.

| Type | Content | Loaded |
|---|---|---|
| `NodeDeviceConfiguration` | One file per node (schema above) | All, at start and on change |
| `DashboardConfiguration` | Dashboard pages and elements | First one |
| `Variable` | Variables and their values | All |
| Matter singletons (`MatterConfigurationStore`) | Bridge configuration and state | At bridge start |

- Matter fabric credentials live separately, in `MatterCredentials` (relative to the content
  root). Absolute or arbitrary paths are not accepted.
- `StoredObjects/outbox.db` (Orchestrator 1.3.0) is the SQLite outbox of workflow triggers waiting
  for delivery ([design 7.1](../design/reliable-delivery.md)). It is runtime state, not configuration: include it in full-system backups,
  not in configuration exports.
- Back up `/app/StoredObjects` and `/app/MatterCredentials`. Both can contain secrets.
- Golden files: [RIoT2.Core/contracts/golden](https://github.com/Revolutionized-IoT2/RIoT2.Core/blob/main/contracts/golden/README.md) has real stored files with
  credentials scrubbed (`stored/`, including a legacy `Rule` file that is no longer loaded) and the
  files the orchestrator writes after loading and saving them (`stored-saved/`), plus the
  `GET /api/nodes/{id}/configuration` response (`http/node-configuration.json`). RIoT2.Tests
  checks that every sample still loads and saves to the same format.

## Plugins (.NET Node)

- Location: `Plugins/` next to the Node executable (`/app/Plugins` in the container).
- At start, the Node loads every `Plugins/*.dll` into a `PluginLoadContext`:
  1. It finds the one non-abstract `IDevicePlugin` class (two make that DLL fail).
  2. It registers the assembly as an ASP.NET application part, so plugin controllers such as
     `/api/webhook/{address}` are served.
  3. It calls `IDevicePlugin.Initialize(IServiceCollection)`: the plugin (a Core `PluginBase`)
     registers its services and devices as singletons, and the node resolves every `IDevice`.
- Assemblies named in Core's `PluginHostContract.SharedAssemblyPrefixes` (`RIoT2.Core*` and the DI
  and logging abstractions) always come from the Node: release the Node image before plugins built
  on a newer Core ([overview](../architecture/overview.md#versioning-and-releases)).
- `GET /api/device/configuration/templates` returns one template per device, built by Core's
  `DeviceTemplates.Create`: the device's own template if it implements `IDeviceWithConfiguration`
  (with its Matter endpoints), otherwise a default one without parameters (refresh schedule
  `0 * * ? * * *` for refreshable devices). A device with typed options
  also gets `parameterDefinitions` and every key, with its default. A device's template declares
  every key the device reads; each plugin's CI checks this (`RIoT2.Core.Devices.Testing`).
- Typed options bind before `ConfigureDevice`: an empty value takes the default; a missing
  required or invalid value puts the device into `Error`, listing every problem in its state.
  The UI renders typed editors and masks `secret` values (stored as plain text).
- `Plugins/PluginManifest.json` (a `PackageManifest`, advertised as `pluginManifest`): `name`,
  `version`, `date`, `installedPackageFilename`, `coreVersion` (the `RIoT2.Core.Devices` version,
  zips since I03) and `sha256` of the installed zip (added by Node 1.14.0). Releases publish a
  `<zip>.sha256` sidecar (`sha256sum` format).
- Package updates (Node 1.14.0, [as built](../design/desired-state-as-built.md#as-built-phase-4-i35)),
  checked before each configuration is applied:
  1. `<pluginPackageUrl>.sha256` is compared with the installed `sha256` (without a sidecar, the
     file name, as before). Plugins whose manifest names no package are kept.
  2. A changed package is downloaded, its hash verified, extracted into `Plugins.new/` and its
     `coreVersion` checked (same Core major, minor no newer than the node's). The node saves the
     configuration, reports `pendingRestart` and restarts.
  3. At the next start `Plugins/` moves to `Plugins.previous/`, `Plugins.new/` to `Plugins/`. If
     the package doesn't load, any previous plugins return and the node exits (code 75), once.
  4. A refused package leaves `Plugins/` alone; the devices apply with the installed plugins and
     the status is `failed`. Refusals other than a hash mismatch are kept in
     `Data/plugins.rejected.json` (delete it to retry).
- Plugins load only at start: **restart the container** after changing them by hand.
- If no plugin loads, the Node logs `NO PLUGINS LOADED` (critical) and keeps running without
  devices. It does not shut down.
- Catalogs: `RIoT2.Net.Devices` (network, cloud) and `RIoT2.Net.RasPi.Devices` (GPIO, I2C,
  Bluetooth, serial, Z-Wave).

## Planned (not implemented)

Signed plugin packages, with the optional security mode (I53).
