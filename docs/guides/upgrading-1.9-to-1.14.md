# Upgrading from Orchestrator 1.9 to 1.14

Applies to: deployments that run Orchestrator 1.9.0 to 1.14.x and Node 1.8.0 to 1.12.x. Read these
sections, oldest last, after the procedure and the newer sections in [upgrading.md](upgrading.md).
Older releases: [upgrading-older.md](upgrading-older.md).

## Supply chain (Orchestrator 1.14.2, Node 1.12.1, Elsa 1.7.2, connector 1.6.3, UI 1.6.1)

No port, user, volume, variable, JSON or behaviour changes; update in any order
([I33](../increments/phase-2.md#i33-supply-chain-s)). The images are rebuilt on digest-pinned
base images and carry an SBOM and provenance, so a tag names an image index; `docker pull` and
compose handle it as before.

## Nullable reference types (Node 1.12.0, Orchestrator 1.14.1, connector 1.6.2, Devices 1.6.0, RasPi.Devices 1.5.0)

No port, user, volume, variable, JSON or behaviour changes
([I32](../increments/phase-2.md#i32-nullable-reference-types-m)). **Update the node to 1.12.0
before installing the Devices 1.6.0 or RasPi.Devices 1.5.0 plugin**, which are built on Core
1.17.0. Older plugins keep working. Plugin authors: Core 1.17.0 is nullable-annotated;
override `Refresh`/`RefreshAsync` with `ReportTemplate?`.

## Async device drivers (Node 1.11.1, Devices 1.5.0, RasPi.Devices 1.4.0)

No port, user, volume, variable or JSON changes; update in any order
([I31](../increments/phase-2.md#i31-async-cleanup-part-2-and-threading-analyzers-m)). Devices 1.5.0
needs Node 1.11.0 or newer, RasPi.Devices 1.4.0 Node 1.10.0. The network devices no longer block
the node while they wait, and a configuration change cancels their requests. Node 1.11.1 puts a
device whose request times out into the error state with the reason, where it used to show
stopped. The Netatmo Weather and Hue templates list what the device read at its last start or
refresh. The RasPi Z-Wave devices open the stick when they start, and close it again when a start
fails.

## Typed device options (Node 1.11.0, Orchestrator 1.14.0, UI 1.6.0, Devices 1.4.0)

No port, user, volume or variable changes; stored configurations and their hashes are unchanged.
**Update the node to 1.11.0 before installing the Devices 1.4.0 plugin**, which is built on Core
1.16.0 ([I30](../increments/phase-2.md#i30-typed-device-options-m)). The node now matches
parameter keys case-insensitively. AzureRelay, EasyPLC, FTP, Mqtt and Messaging validate their
parameters at start: a missing required value (Mqtt `serverUrl`, EasyPLC `ipAddress`, all four
AzureRelay keys) or a non-numeric port puts the device into the error state, with the reason in
its status, where it used to fall back silently. EasyPLC's `port` now defaults to 10001 and FTP's
`ftpPort` to 21. The UI shows typed fields and hides secrets for devices of an online node; update
it with the orchestrator (the order doesn't matter).

## Plugin packaging (Devices and RasPi.Devices 1.3.1)

No image changes. The 1.3.1 plugin zips hold the same files as 1.3.0 and need Node 1.10.0 or
newer, like 1.3.0; their build now packs them ([I29](../increments/phase-2.md#i29-plugin-packaging-s)).
Plugin authors: reference `RIoT2.Core.Devices.Build` and set `RIoT2PluginName`.

## Narrow Core references (Orchestrator 1.13.1, Node 1.10.0, Elsa 1.7.1, connector 1.6.1, UI 1.5.0)

Skip Orchestrator 1.13.0, Elsa 1.7.0 and connector 1.6.0: they fail at start (a missing
`Microsoft.Bcl.AsyncInterfaces`). No port, user, volume, variable or JSON changes. Each service references only the Core packages
it uses ([I28](../increments/phase-2.md#i28-narrow-references-and-generated-models-m)). **Update the node to 1.10.0 before installing the
1.3.0 plugins** (RIoT2.Net.Devices, RIoT2.Net.RasPi.Devices): they are built against Core 1.14.0,
and an older node doesn't load them. Installed older plugins keep working on Node 1.10.0.

## Core package split (Orchestrator 1.12.0, Node 1.9.0)

No port, user, volume, variable or JSON changes; update in any order. Installed plugins keep
working; a plugin rebuilt against RIoT2.Core 1.13.0 needs Node 1.9.0.

## Typed persistence (Orchestrator 1.11.0)

No port, user, volume or variable changes. The stored configuration keeps its format, and a return
to 1.10.0 reads it; take a backup first anyway (this release changes the storage code). Emoji are
written unescaped again, as before 1.10.0, so a node whose configuration has one re-applies it once. At its first start the orchestrator moves the retired rule engine's
`StoredObjects/Rule` files to `StoredObjects/.archive/Rule` and logs a warning. The
`json-naming-policy` request header is deprecated: answers carry `Deprecation: true`, and
Orchestrator 1.19.0 removes it (I45). Scripts that send it should use the default camelCase.

## System.Text.Json (Orchestrator 1.10.0, Node 1.8.0, Elsa 1.6.0, connector 1.5.0)

No port, user, volume or variable changes; update in any order. The JSON on MQTT, over HTTP and in
`StoredObjects/` is the same, so configuration hashes don't change and no node re-applies its
configuration. For plugin authors (RIoT2.Core 1.11.0): an `object` member read from JSON holds a
`JsonElement` for an object or array instead of a `JObject`, and invalid JSON throws
`System.Text.Json.JsonException`. Existing plugin builds keep working.

## UI restructure (UI 1.4.0)

No port, user, volume or variable changes; works with Orchestrator 1.7.0 or later. The UI now
announces itself on every MQTT connection and when the orchestrator restarts, so open pages no
longer stay on "Connecting..." after a restart. Its presence is camelCase; every orchestrator reads
it. Menu labels: **Workflows** (was Rules) and **Variables**.

## Orchestrator restructure (Orchestrator 1.9.0)

No port, user, volume, variable or route changes; update in any order. Two template listings gain
fields: `GET /api/nodes/report/templates` has each template's `model` (it was `null`), and
`GET /api/nodes/variable/templates` an empty `address`. The UI ignores both.
