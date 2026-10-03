# Node configuration, templates, persistence and plugins

Applies to: Orchestrator (stores and serves configuration), Node, firmware, device plugins, UI
(edits configuration).

Source of truth:

| Topic | Code |
|---|---|
| Models | `RIoT2.Core/Models/NodeDeviceConfiguration.cs`, `DeviceConfiguration.cs`, `ReportTemplate.cs`, `CommandTemplate.cs`, `Models/Matter/*` |
| Firmware model | `RIoT2.Ard.Shared/RIoT2Shared/include/riot2/DeviceConfiguration.h`, `src/OrchestratorClient.cpp` |
| Persistence | `RIoT2.Net.Orchestrator/Services/Persistence/FileObjectStore.cs` |
| Plugin loading | `RIoT2.Net.Node/Program.cs`, `RIoT2.Core/Abstracts/NodeConfigurationServiceBase.cs` |

## How configuration flows

1. The user creates a node in the UI with the same id as the node's `RIOT2_NODE_ID` (or the
   firmware's provisioned id). The UI adds devices, picked from the templates that the online node
   reports (`GET /api/nodes/{id}/device/templates`). The UI saves with
   `POST /api/nodes/configuration`.
2. The orchestrator persists the configuration. When the node comes online, the orchestrator
   publishes `riot2/node/{id}/configuration` ([mqtt-topics.md](mqtt-topics.md#lifecycle)).
3. The node fetches `GET {apiBaseUrl}/api/nodes/{id}/configuration` and replaces its device set:
   - Old work is cancelled and awaited, and old devices are stopped.
   - New devices are initialized and started. Devices removed from the configuration stay
     stopped.
4. If the configuration contains a `pluginPackageUrl` whose file name differs from the installed
   package, the .NET Node downloads the package. It is installed on the next start
   ([Plugins](#plugins-net-node)).

## Schema (`GET /api/nodes/{id}/configuration`)

Serialized by the orchestrator with `Json.Serialize` (Newtonsoft, camelCase, enums as numbers):

```json
{
  "id": "F811B5A0-E978-45BB-ADD3-584655DF21BF",
  "name": "Garage node",
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
| `classFullName` | Full .NET type name of the device class in a loaded plugin, or the firmware view/peripheral class name. This is how the node finds the implementation. |
| `deviceParameters` | Device settings (`Dictionary<string,string>`), read by `DeviceBase.GetConfiguration<T>(key)`, which is **case-sensitive**. May contain third-party secrets; never commit them. |
| `refreshSchedule` | Optional Quartz cron expression for refreshable devices. Validate with `POST /api/nodes/validatecron`. |
| `reportTemplates[].id` | Globally unique. Becomes `Report.id`. The orchestrator ignores reports without a matching template. |
| `reportTemplates[].type`, `commandTemplates[].type` | `ValueType`: `0` Boolean, `1` Text, `2` Number, `3` Entity, `4` TextArray |
| `reportTemplates[].address`, `commandTemplates[].address` | Device-specific address, e.g. the webhook path segment for the Web device, or an MQTT topic for the generic MQTT device. |
| `reportTemplates[].parameters` | Display hints such as `unit` and `precision` |
| `reportTemplates[].filters` | Allowed `Report.filter` values |
| `reportTemplates[].maintainHistory` | The orchestrator keeps history (`/api/dashboard/report/{id}/history`) |
| `model` | Example or default value. `CommandTemplate.GetAsCommand()` uses it as the default command value. |
| `commandTemplates[].id` | Globally unique. The orchestrator maps a `Command.id` to the owning node. |
| `matterEndpoints` | Optional Matter bridging declarations (`MatterEndpointTemplate`, see the `RIoT2.Core` README) |

Variables (`Variable`, `VariableTemplate`) are orchestrator-side values. They can be used as
command targets from Elsa (`RIoTOutput`) and are read with `/api/variable/{id}/value`.

### Firmware subset

The firmware parses only `id`, `name`, and `deviceConfigurations[]`, and from each device only:

- `id`, `name`, `classFullName`
- `deviceParameters` (as string pairs)
- `commandTemplates[]`: `id`, `type`, `name`, `address`, `valueType`, `model`
- `reportTemplates[]`: `id`, `type`, `name`, `address`, `parameters`

It ignores `refreshSchedule`, `matterEndpoints`, `filters` and `maintainHistory`. On-screen views
and Grove peripherals are both entries in `deviceConfigurations`, told apart by `classFullName`.
Responses larger than 32 KiB are rejected.

## Known divergences

| # | Divergence | Impact |
|---|---|---|
| C1 | `Json.Serialize` uses `CamelCasePropertyNamesContractResolver`, which also camel-cases **dictionary keys**. A device that reads `GetConfiguration("StorageIp")` receives `storageIp` and gets the default value. Example: `RIoT2.Net.Devices/Catalog/FTP.cs` (`Storage*` keys). | Use camelCase parameter keys in new devices. Fixing it needs either a Core change or renaming the keys. |
| C2 | Firmware reads template `type` as a string and `valueType` as a number. The orchestrator sends `type` as a number and never sends `valueType`, so the parsed values are `""` and `0`. | Firmware views build their own templates, so this doesn't matter today. Check before relying on downloaded types in firmware. |

## Orchestrator persistence (`StoredObjects`)

- Layout: `<content-root>/StoredObjects/<TypeName>/<id>.json`, which in the container is
  `/app/StoredObjects/...`.
- Type names and ids are validated as safe file names (no path traversal). Never build paths
  from raw ids.

| Type | Content | Loaded |
|---|---|---|
| `NodeDeviceConfiguration` | One file per node (schema above) | All, at start and on change |
| `DashboardConfiguration` | Dashboard pages and elements | First one |
| `Variable` | Variables and their values | All |
| Matter singletons (`MatterConfigurationStore`) | Bridge configuration and state | At bridge start |

- Matter fabric credentials live separately, in `MatterCredentials` (relative to the content
  root). Absolute or arbitrary paths are not accepted.
- Back up `/app/StoredObjects` and `/app/MatterCredentials`. Both can contain secrets.

## Plugins (.NET Node)

- Location: `Plugins/` next to the Node executable (`/app/Plugins` in the container).
- At start, the Node loads every `Plugins/*.dll` into a `PluginLoadContext`:
  1. It finds the `IDevicePlugin` implementation.
  2. It registers the assembly as an ASP.NET application part, so plugin controllers such as
     `/api/webhook/{address}` are served.
  3. It calls `IDevicePlugin.Initialize(IServiceCollection)`.
- `Plugins/PluginManifest.json` (a `PackageManifest`) identifies the installed package, and is
  advertised as `pluginManifest`.
- Package updates:
  1. The configuration's `pluginPackageUrl` is checked with a `HEAD` request (`Content-Disposition`
     file name).
  2. A new package is downloaded to `Data/`.
  3. On the next start, the first `Data/*.zip` **replaces the entire contents** of `Plugins/` and
     is then deleted. Zip entries that would escape `Plugins/` are rejected.
- Plugins load only at start, so **restart the container** after changing plugins.
- If no plugin loads, the Node logs `NO PLUGINS LOADED` (critical) and keeps running without
  devices. It does not shut down.
- Plugins run against the Node's `RIoT2.Core` version. Release the Node image and the plugin
  package together ([architecture overview](../architecture/overview.md#versioning-and-releases)).
- Device catalogs: `RIoT2.Net.Devices` (network and cloud devices) and `RIoT2.Net.RasPi.Devices`
  (GPIO, I2C, Bluetooth, serial, Z-Wave).

## Planned (not implemented)

PLATFORM-REVIEW design 7.2 (desired-state configuration) adds a revision and hash to
configurations, plus a retained `riot2/node/{id}/status` topic, a last-good-configuration cache,
and verified plugin installs with rollback.
