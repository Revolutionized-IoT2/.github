# MQTT topics and payloads

Applies to: every component that connects to the MQTT broker (Orchestrator, Node, Elsa,
connectors, ESP32 firmware, UI).
Source of truth: `RIoT2.Core/Constants.cs` (topics), `RIoT2.Core/Models/*.cs` (payloads),
`RIoT2.Ard.Shared/RIoT2Shared/include/riot2/Topics.h` (firmware copy of the topics).
If this document and the code disagree, the code wins. Fix this document.

## Topics

| Enum (`MqttTopic`) | Template | Payload | Retained |
|---|---|---|---|
| `NodeOnline` (1) | `riot2/node/{id}/online` | `NodeOnlineMessage` | Yes (.NET from Core 1.8.0, Node 1.5.0) |
| `Configuration` (2) | `riot2/node/{id}/configuration` | `ConfigurationCommand` | No |
| `Command` (3) | `riot2/node/{id}/command` | `Command` | No |
| `Report` (4) | `riot2/node/{id}/report` | `Report` | No |
| `OrchestratorOnline` (5) | `riot2/orchestrator/online` | `{"isOnline":true}`, or `{"isOnline":false}` after a stop or a dropped connection | Yes |
| `CommandResult` (6) | `riot2/node/{id}/command/result` | `CommandResult` (Core 1.6.0; used from Node 1.4.0 and Orchestrator 1.4.0) | No |
| `NodeStatus` (7) | `riot2/node/{id}/status` | `NodeStatusMessage` (Core 1.6.0; used from Node 1.5.0 and Orchestrator 1.5.0) | Yes |

`{id}` is the MQTT client id of the participant, which is also its RIoT2 id:

| Participant | Id source |
|---|---|
| Orchestrator | `RIOT2_ORCHESTRATOR_ID` |
| .NET Node | `RIOT2_NODE_ID` |
| Elsa | `RIOT2_WORKFLOW_ID` |
| InfluxDB connector | `RIOT2_CONNECTOR_ID` |
| Firmware | Provisioned node id (stored in NVS) |

Build and parse topics with `Constants.Get(id, MqttTopic.X)` and `Constants.GetTopicId(topic, MqttTopic.X)`.
Don't hard-code topic strings in .NET code.

## Who publishes and subscribes

| Topic | Publishers | Subscribers (exact filter) |
|---|---|---|
| `riot2/orchestrator/online` | Orchestrator: `true` on every (re)connect; `false` from its last will and on a graceful stop (Core `1.1.0`, `MqttClient.SetLastWill`) | Node, Elsa, InfluxDB connector, firmware. They re-announce themselves on any message on this topic, whatever its payload. |
| `riot2/node/{id}/online` | Node, Elsa, connector, firmware (on connect and after seeing orchestrator online). UI (once, at page load). Every client's last will. | Orchestrator: `riot2/node/+/online` |
| `riot2/node/{id}/configuration` | Orchestrator, after every online message with `isOnline:true` and after the node's configuration is saved | The node with that id (Node, Elsa, connector, firmware, UI) |
| `riot2/node/{id}/command` | Orchestrator (from `POST /api/command/execute` and Elsa workflows) | The node with that id. InfluxDB connector: `riot2/node/+/command` (only when `RIOT2_HANDLE_COMMANDS=true`) |
| `riot2/node/{id}/report` | Node, firmware, Orchestrator (its own reports, under its own id) | Orchestrator, InfluxDB connector, UI: `riot2/node/+/report` |
| `riot2/node/{id}/command/result` | .NET Node (Node 1.4.0), for every command with a `correlationId` | Orchestrator: `riot2/node/+/command/result` (Orchestrator 1.4.0) |
| `riot2/node/{id}/status` | .NET Node (Node 1.5.0): on every connect, before its presence, and whenever its configuration state changes. Orchestrator: an empty retained payload when the node's configuration is deleted. | Orchestrator: `riot2/node/+/status` (Orchestrator 1.5.0) |

- The UI is a **Dashboard node** (`nodeType` 2) with a new random id on every page load. It
  connects to the broker over WebSockets (`ws://<VITE_MQTT_SERVER>:9001/`) and announces itself on
  `riot2/node/{id}/online`. It learns the orchestrator URL from its `configuration` message and
  follows reports live. It announces itself only once (backlog item 21).
- RIoT2.Mobile does not use MQTT. Push notifications use Firebase Cloud Messaging topics `alerts`
  and `notifications`.

## Payloads

All payloads are UTF-8 JSON with camelCase property names. .NET publishers use
`Json.SerializeIgnoreNulls`, so `null` properties are omitted. Readers must ignore unknown
properties, because new fields are added without a version bump.

Every payload below has a golden example in [RIoT2.Core/contracts/golden/messages](https://github.com/Revolutionized-IoT2/RIoT2.Core/blob/main/contracts/golden/README.md):
one `Report` and one `Command` per `ValueType`, `node-online`, `node-offline` (the default last
will) and `configuration-command`. The .NET, Elsa, UI and firmware tests read them, so a format
change fails their CI.

### `Report` (`RIoT2.Core/Models/Report.cs`)

```json
{ "id": "livingroom-temperature", "timeStamp": 1790253852, "filter": "room", "value": 21.5 }
```

- `id` is the report template id. The orchestrator drops reports whose id doesn't match a
  configured report template.
- `timeStamp` is Unix epoch seconds, UTC (`ToEpoch()` / `FromEpoch()`).
- `filter` is optional. Firmware never sends it.
- `value` is any JSON value (see [`ValueModel`](#valuemodel)).

### `Command` (`RIoT2.Core/Models/Command.cs`)

```json
{ "id": "livingroom-lamp", "value": { "on": true, "brightness": 80 } }
```

`id` is the command template id. The orchestrator finds the owning node with
`FindNodeId(command.Id)` and publishes to that node's command topic.

From Orchestrator 1.4.0 every command goes through its outbox and carries a `correlationId` (one
per delivery; a redelivery repeats it):

```json
{ "id": "livingroom-lamp", "value": true, "correlationId": "4b8f0c2d9e7a41c3b5d6e8f901a2b3c4" }
```

A node that advertises `command-result/1` answers it with a `CommandResult`. Older nodes ignore the
field. A command without a `correlationId` gets no result, as before.

Reserved command id: `system.ota` (firmware only). `value` is a firmware `.bin` URL, and it is
handled before view dispatch. Don't assign it to a command template. Since firmware 0.2.0 the new
image rolls back by itself unless it fetches its configuration within 3 minutes, and a
`system.ota` that arrives during that time is refused.

### `CommandResult` (`RIoT2.Core/Models/CommandResult.cs`)

```json
{ "correlationId": "4b8f…", "commandId": "livingroom-lamp", "status": "failed", "error": "relay stuck", "timeStamp": 1790253852, "contractVersion": 1 }
```

`status` (`CommandResultStatus`):

| Status | The .NET Node sends it when | The orchestrator then |
|---|---|---|
| `executed` | the device ran the command without an exception | marks it executed and sets the command state |
| `failed` | the device threw (`error` has the message) | marks it failed |
| `unknownCommand` | no device on the node owns the command | marks it failed with that status |
| `rejected` | 64 commands are pending, it is stopping, or the device or configuration isn't ready | sends it again after a backoff |
| `duplicate` | it executed the `correlationId` in the last 10 minutes (256 ids at most); not run again | marks it done and sets the command state |

A redelivery is never run twice: while the first delivery runs it gets no answer of its own (the first
result answers both), and a redelivery of a failed or unknown command gets that result again. A
command cancelled by a node shutdown gets no result; the restarted node runs its redelivery. One
cancelled because its device was stopped or reconfigured is `failed`.

### `ConfigurationCommand` (`RIoT2.Core/Models/ConfigurationCommand.cs`)

```json
{ "apiBaseUrl": "http://192.168.0.32", "revision": 42, "hash": "9f2c?" }
```

`apiBaseUrl` is the orchestrator's `RIOT2_ORCHESTRATOR_URL`. `revision` and `hash` (Orchestrator
1.5.0, omitted for a node without a configuration) identify the node's saved configuration; a node
that already runs that `hash` doesn't fetch it again ([configuration.md](configuration.md#desired-state)).
Receivers use `apiBaseUrl` as follows:

- Node and firmware: fetch `{apiBaseUrl}/api/nodes/{id}/configuration`
  ([http-api.md](http-api.md), [configuration.md](configuration.md)).
- Elsa: stores it as the orchestrator base URL.
- Connector: loads the template catalogs from it.

### `NodeStatusMessage` (`RIoT2.Core/Models/NodeStatusMessage.cs`)

```json
{ "appliedRevision": 42, "appliedHash": "9f2c?", "state": "applied", "failedDevices": [{ "id": "plc", "message": "unreachable" }], "pluginManifest": { ? }, "timeStamp": 1790253852, "contractVersion": 1 }
```

A .NET node's view of its configuration (design 7.2). `state` (`NodeConfigurationState`) is
`applying` (also before the first configuration), `applied` (`failedDevices` lists the configured
devices that aren't running), `failed` (`error` says why; the node runs the applied revision) or
`pendingRestart` (a new plugin package installs on restart). `appliedRevision` and `appliedHash`
are absent when nothing is applied or the orchestrator sent none. Meaning of each state and the
orchestrator's sync state: [configuration.md](configuration.md#desired-state).

### `NodeOnlineMessage` (`RIoT2.Core/Models/NodeOnlineMessage.cs`)

```json
{
  "name": "Garage node",
  "isOnline": true,
  "nodeBaseUrl": "http://192.168.0.33",
  "grpcBaseUrl": "http://192.168.0.32:5003",
  "nodeType": 1,
  "manifest":       { "name": "RIoT2 Node", "version": "1.2.0", "date": "…", "installedPackageFilename": "…" },
  "pluginManifest": { "name": "…", "version": "…", "date": "…", "installedPackageFilename": "…" }
}
```

| Field | Notes |
|---|---|
| `isOnline` | `false` in last-will and graceful-stop messages. The orchestrator then removes the node from its online list. It ignores an empty payload (a cleared retained message) and an unreadable one with a warning. |
| `nodeBaseUrl` | The base URL that the orchestrator uses to call the node's HTTP API (`RIOT2_NODE_URL`, `RIOT2_WORKFLOW_URL`, or `http://<ip>` for firmware). |
| `grpcBaseUrl` | Workflow nodes only (`RIOT2_WORKFLOW_GRPC_URL`). The orchestrator prefers it over `nodeBaseUrl` for gRPC triggers. |
| `nodeType` | `0` Unknown, `1` Device (Node, firmware), `2` Dashboard (UI), `3` Workflow (Elsa). The connector sends no type (0). |
| `manifest`, `pluginManifest` | `PackageManifest` of the node image and of the installed plugin package (.NET Node). |
| `capabilities` | Optional features (`Contract.Capabilities`). `command-result/1`: the node answers commands with a `CommandResult` (.NET Node 1.4.0). `desired-state/1`: it publishes its status and skips a configuration it runs (.NET Node 1.5.0). |

### `ValueModel`

`Report.value` and `Command.value` are `ValueModel` instances. They store the raw JSON value, not
a `{type, value}` envelope. The type is inferred from the JSON kind:

| JSON kind | `ValueType` |
|---|---|
| boolean | `Boolean` (0) |
| string, null | `Text` (1) |
| number | `Number` (2) |
| object | `Entity` (3) |
| array | `TextArray` (4) |

Large integers and JSON-looking strings are preserved as-is (since Core 0.1.40).

## Lifecycle and delivery

How participants announce themselves and get their configuration, the QoS levels and what is lost
when, are in [mqtt-delivery.md](mqtt-delivery.md).

## Known divergences

These differences exist in the code today. Fix them in the code, or document them here as
intentional. Don't copy them into new code. Fixed divergences are removed and their IDs are never
reused: D1 (.NET presence wasn't retained; fixed in [I16](../increments/phase-2.md#i16-desired-state-configuration-for-net-nodes-m)), D2 (the orchestrator's last will went to its node topic; fixed in [I04](../increments/phase-0-1.md#i04-restart-only-changed-devices-s)) and D4
(.NET published at QoS 2 but subscribed at QoS 0; fixed in [I08](../increments/phase-0-1.md#i08-mqtt-client-robustness-m)).

| # | Divergence | Where |
|---|---|---|
| D3 | The UI's presence and last-will payloads are PascalCase (`{"IsOnline":true,"Name":…,"NodeType":2}`). .NET readers are case-insensitive, but other readers may not be. | `RIoT2.UI/src/App.vue`, `RIoT2.UI/src/composables/mqttService.ts` |
| D5 | Firmware builds `api/Nodes/{id}/configuration` (capital `N`). It works because ASP.NET routing is case-insensitive. | `OrchestratorClient.cpp` |

## Planned changes (not implemented)

Planned in [design 7.1](../design/reliable-delivery.md) and [design 7.2](../design/desired-state-configuration.md). All of them are
additive. Command results (I15) and desired state for .NET nodes (I16) are in use (above).

- Command results and desired state from firmware (designs 7.1 phase 3 and 7.2 phase 5, I19):
  firmware advertises neither capability yet, so its commands are `sent` and it shows as `legacy`.
- `contractVersion` ([ADR 0005](../adr/0005-split-core-packages.md)): an optional field on every
  payload. It is absent (meaning 1) unless a producer sets it; the two new messages carry
  `"contractVersion": 1`. It changes only with a breaking change, which still needs an ADR.
- QoS 1 in firmware (.NET clients use it since Core 1.3.0).

Unset, the new fields are omitted, so today's payloads are byte-for-byte unchanged.

## Rules for changing this contract

- Changes must be additive: new optional fields, new topics. Never rename or remove a field or
  topic without an ADR and a migration plan for firmware, which updates more slowly.
- A change touches, in order:
  1. `RIoT2.Core` (and a Core release)
  2. `RIoT2.Ard.Shared` (`Topics.h`, `MqttJson`)
  3. the consumers
  4. this document
- Regenerate the golden files (RIoT2.Tests with `RIOT2_UPDATE_GOLDEN=1`) and run every consumer's
  tests listed in their README.
- Keep payloads camelCase, and serialize with `Json.SerializeIgnoreNulls`.
