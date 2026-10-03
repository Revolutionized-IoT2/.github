# Design 7.2: Desired-state configuration and plugin updates (A4)

Applies to: see below. Status: **proposed, not implemented**. Written for the September 2026
platform review; "current behaviour" describes the code at that time. Verify before starting.
Design IDs `7.1`–`7.5` are stable. Architecture context: [target.md](../architecture/target.md).

## Current behaviour (verified in code)

- The orchestrator publishes `ConfigurationCommand{apiBaseUrl}` on `riot2/node/{id}/configuration`
  in three cases: whenever a node announces itself online, whenever its `NodeDeviceConfiguration`
  is saved, and indirectly whenever the orchestrator starts. On start the orchestrator publishes
  the retained `riot2/orchestrator/online` message, which makes every node re-announce itself.
- The node fetches `GET {apiBaseUrl}/api/nodes/{id}/configuration` and calls
  `ReconfigureDevicesAsync`, which **stops and restarts every device on the node** even when
  nothing changed.

  As a result, every MQTT reconnect, every orchestrator restart and every save of any field
  restarts all devices on the affected nodes. Devices drop connections, lose in-memory state and
  can miss events ([5.1 item 18](../backlog/open-issues.md)).
- There is no revision, and the node doesn't report what it applied. Errors are visible only in
  the node log and in the per-device status, which the orchestrator fetches over REST.
- The .NET node doesn't cache configuration. If the orchestrator is unreachable when the node
  starts, the node runs with no devices. Firmware already caches its configuration in flash
  (`ConfigCache`).
- **Plugin updates:**
  - The node sends `HEAD` to `pluginPackageUrl` and compares the `Content-Disposition` file name
    with `PluginManifest.installedPackageFilename`. This is fragile behind redirects such as
    GitHub release downloads.
  - It downloads the zip to `Data/`, calls `StopApplication()` and relies on the container
    restart policy.
  - On the next start `InstallPluginPackage` deletes `Plugins/` before extracting. A bad zip
    leaves the node without plugins, and there is no hash check or rollback.
- Devices are matched to configuration by `ClassFullName` (one instance per class per node).

## Goals

1. Apply only real changes, and restart only the devices whose configuration changed.
2. Nodes report their applied revision and result, so the UI can show "in sync / applying / failed".
3. Nodes start from their last good configuration when the orchestrator is down.
4. Plugins are integrity-checked, compatibility-checked and installed with rollback.
5. Old and new nodes and orchestrators work in any combination.

Non-goals: pushing the full configuration over MQTT (firmware caps the configuration at 32 KiB, and
HTTP fetch works fine), and signing ([A1](../architecture/target.md#a1-optional-security-mode)).

## Decisions

1. **Revision and hash.** The orchestrator stores `revision` (an integer per node, incremented on
   every save that changes content) and `hash` (lowercase hex SHA-256 of the configuration exactly
   as served by the GET endpoint) with each `NodeDeviceConfiguration`. Nodes compare **hashes**:
   they stay correct even if revisions reset after a backup restore. Revisions are for people and
   the UI.
2. **Per-device hash.** Each `DeviceConfiguration` in the served document also carries a `hash`, so
   a node can work out which devices to restart without re-serializing anything itself.
3. **Status topic.** A new retained topic, `riot2/node/{id}/status`, holds the node's view of its
   configuration. It is separate from `online`, which stays a presence signal. Being retained, it
   lets a restarted orchestrator see the state of every node immediately.
4. **Cache.** The .NET node writes the last successfully applied document to
   `Data/configuration.applied.json`, and applies it at startup before MQTT connects. This mirrors
   the firmware's `ConfigCache`.
5. **Failure policy.**
   - If fetching or parsing fails, the node keeps running the previous configuration and reports
     `failed`.
   - If individual devices fail to start, the node reports `applied` and lists the failing devices.
     The configuration itself was applied; the device errors are already reported per device.
6. **Plugins.**
   - CI publishes a sidecar `<package>.zip.sha256` next to each release zip, and adds
     `coreVersion` (the Core version the plugin was built against) and `sha256` to
     `PluginManifest.json`.
   - The node downloads the zip and the sidecar, and verifies the hash. A missing sidecar logs a
     warning and continues, for legacy packages; strict mode comes with A1.
   - The node then extracts into `Plugins.new/` and checks that `coreVersion` matches its own Core
     major.minor. It renames `Plugins/` to `Plugins.previous/` and `Plugins.new/` to `Plugins/`,
     publishes status `pendingRestart`, and calls `StopApplication()`.
   - If loading plugins fails at startup and `Plugins.previous/` exists, the node swaps back and
     restarts once. A marker file prevents a restart loop. The node then reports `failed` with the
     reason.
   - Change detection compares the sidecar hash with the installed manifest's `sha256`, falling back
     to today's file-name comparison when there is no sidecar.

## Contract changes (all additive)

| Item | Change |
|---|---|
| `ConfigurationCommand` | `{ "apiBaseUrl": "…", "revision": 42, "hash": "9f2c…" }`. Old nodes ignore the new fields and keep fetching every time. |
| `NodeDeviceConfiguration` (GET response) | Adds `revision`, `hash`, and `hash` on each `deviceConfigurations[]` entry. The response also sends `ETag: "<hash>"` and honours `If-None-Match` with `304`. |
| New `NodeStatusMessage` on `riot2/node/{id}/status` (retained) | `{ "appliedRevision": 42, "appliedHash": "9f2c…", "state": "applied" \| "applying" \| "failed" \| "pendingRestart", "error": "…", "failedDevices": [{ "id": "…", "message": "…" }], "pluginManifest": { … }, "timeStamp": 1790000000 }` |
| `NodeOnlineMessage` | `capabilities` includes `desired-state/1` (the same field as in [7.1](reliable-delivery.md)). |
| `PluginManifest.json` | Adds `coreVersion` and `sha256`. |
| REST | `GET /api/nodes` adds `desiredRevision`, `appliedRevision`, `syncState` (`inSync`, `pending`, `failed`, `legacy`) and `lastError` for each node. |

## Behaviour on each side

- **Orchestrator.**
  - Computes the revision and hash on save.
  - Subscribes to `riot2/node/+/status`.
  - For nodes with `desired-state/1`, sends the configuration command only when the reported
    `appliedHash` differs from the desired hash (on online, on save, and on a status mismatch).
  - For legacy nodes it keeps today's behaviour.
- **.NET node.**
  1. When a configuration command arrives, if its `hash` equals the applied hash, republish the
     status and stop.
  2. Otherwise fetch (with `If-None-Match`) and publish `applying`.
  3. Diff devices by `ClassFullName` and per-device `hash`. Stop and reinitialize only the added,
     removed or changed devices; this needs a `ReconfigureChangedDevicesAsync` in
     `DeviceServiceBase`.
  4. Save the cache and publish `applied`.

  A command without a `hash` (old orchestrator) is always treated as changed, but the per-device
  diff still prevents unnecessary restarts.
- **Firmware.**
  - Skip the refetch when the command's `hash` equals the cached one.
  - Publish a compact status (no `failedDevices` list beyond 4 entries, to stay well under
    `MQTT_MAX_PACKET_SIZE`).
  - Advertise the capability.

  Firmware has no plugins; OTA rollback is [5.1 item 6](../backlog/open-issues.md).

## Compatibility matrix

| Orchestrator | Node | Result |
|---|---|---|
| new | old (.NET or firmware) | Works as today. The node shows as `legacy` in the UI. |
| old | new | The node fetches on every command (no hash), but only changed devices restart, it caches, and plugin installs are safe. Its retained status message is ignored harmlessly. |
| new | new | Full behaviour. |

## Implementation phases

| Phase | Repos | Content |
|---|---|---|
| 0 (quick fix, no contract change) | Core, Node | The node hashes the fetched document itself and skips `ReconfigureDevicesAsync` when it is identical to the applied one. Add a per-device diff by `ClassFullName` and serialized `DeviceConfiguration`. This fixes 5.1 item 18 on its own and can ship right away. |
| 1 | Core | `revision`/`hash` fields, `NodeStatusMessage`, `MqttTopic.NodeStatus`, `capabilities`. Released together with 7.1 phase 2. |
| 2 | Orchestrator | Revision and hash on save, ETag/304, status subscription, conditional configuration commands, sync fields in `GET /api/nodes`. |
| 3 | Node | Hash short-circuit, cache at startup, status publishing, `If-None-Match`. |
| 4 | Devices/RasPi CI, Node | Sidecar hash and `coreVersion` in CI (also fixes the hand-maintained DLL list in [backlog item 1](../backlog/open-issues.md)); staged install, compatibility check and rollback in the node. |
| 5 | Ard.Shared, both firmwares | Hash short-circuit, status and capability. |
| 6 | UI | Sync badge, applied/desired revision, last error and plugin version per node; a "re-apply" action that forces a configuration command. |

**Tests** ([M7](../plans/m07-contract-integration-tests.md) harness):

- An MQTT reconnect and an orchestrator restart cause **zero** device restarts (count
  `StartDevice` calls on the Virtual device).
- Changing one device restarts only that device.
- A failed fetch keeps the previous configuration and reports `failed`.
- A node started with the orchestrator down runs from its cache.
- A hash mismatch and an incompatible `coreVersion` are both rejected without touching `Plugins/`.
- A plugin that fails to load is rolled back once, with no restart loop.
- All three rows of the compatibility matrix are covered, using the legacy code paths.

## Open points (defaults chosen)

- Hash over the served bytes rather than a canonical JSON form. This is simpler, and correct
  because the orchestrator is the only producer.
- `coreVersion` compatibility is checked on major.minor. That is strict, and matches how Core
  versions are used today.
- A retained status per node. The retained message has to be cleared when a node is deleted: the
  orchestrator publishes an empty retained payload.
