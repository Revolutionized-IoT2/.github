# HTTP and gRPC APIs

Applies to: Orchestrator, Node and device plugins, Elsa, InfluxDB connector, firmware, UI.
Source of truth: controller attributes and `Map*` calls in each repository's code. URLs shared
across repositories are constants in `RIoT2.Core/Constants.cs`.
All APIs are anonymous by design ([ADR 0002](../adr/0002-isolated-network-security-model.md)).

## Conventions

- JSON is camelCase. Enums are serialized as numbers.
- The orchestrator also honours the request header `json-naming-policy: pascal|lower`, which
  switches the controller output casing (`RIoT2.Net.Orchestrator/CustomJsonSettings/Formatters.cs`).
- Responses written with `Json.Serialize` (for example the node configuration) also camel-case
  **dictionary keys**. This affects `deviceParameters`; see [configuration.md](configuration.md).
- Every service container exposes `GET /health`. Elsa and the connector also expose `/healthz`.
- The orchestrator's routes are also written to
  [openapi/riot2-orchestrator.json](https://github.com/Revolutionized-IoT2/RIoT2.Net.Orchestrator/blob/main/openapi/riot2-orchestrator.json)
  by every build. The UI tests fail when the UI calls a route or method that isn't in it. Response
  bodies written with `Json.Serialize` have no schema there; their formats are the golden files in
  [RIoT2.Core/contracts/golden/http](https://github.com/Revolutionized-IoT2/RIoT2.Core/blob/main/contracts/golden/README.md).
- New endpoints must not change state on `GET`. The existing state-changing `GET`s are listed
  below as legacy; don't add more.
- Ports: see [env-vars.md](env-vars.md#ports-volumes-and-images).

## Cross-repository URLs

| URL | Served by | Called by | Constant |
|---|---|---|---|
| `GET /api/nodes/{id}/configuration` | Orchestrator | Node (`NodeConfigurationServiceBase`), firmware (`OrchestratorClient`), UI | `ApiConfigurationUrl` |
| `GET /api/device/configuration/templates` | Node; firmware (`ConfigTemplateServer`, port 80) | Orchestrator (`OnlineNodeService`, via `nodeBaseUrl`) | `ApiConfigurationTemplateUrl` |
| `GET /api/device/status` | Node | Orchestrator (`OnlineNodeService`, via `nodeBaseUrl`) | `ApiDeviceStateUrl` |
| `POST /riot/trigger/{id}` | Elsa | Nothing today (the orchestrator uses the gRPC equivalent) | `ApiWorkflowTriggerUrl` |
| gRPC `riot.RIoTTriggerService/Trigger` | Elsa | Orchestrator (`ElsaAutomationProvider`, through the outbox) | `riot_trigger.proto` / `riot.proto` |

## Orchestrator (`RIoT2.Net.Orchestrator/Controllers`)

Base: `RIOT2_ORCHESTRATOR_URL`. CORS allows any origin, method and header.

### Nodes and configuration (`NodesController`, `api/nodes`)

| Method | Route | Purpose | Main callers |
|---|---|---|---|
| GET | `/api/nodes` | Every configured node: online state, device states (fetched from the node), manifests and, from Orchestrator 1.5.0, `desiredRevision`, `appliedRevision`, `syncState` (`inSync`, `pending`, `failed`, `legacy`) and `lastError` ([configuration.md](configuration.md#desired-state)) | UI |
| GET | `/api/nodes/online` | Online nodes (from `NodeOnlineMessage`s) | UI |
| GET | `/api/nodes/{id}/configuration` | Node configuration, with `revision` and `hash` from Orchestrator 1.5.0. The `ETag` is the hash; a matching `If-None-Match` gets `304`. `?state=true` returns a copy with each command template's last value as `model`, without an `ETag`. | Node, firmware, UI |
| POST | `/api/nodes/configuration` | Save a node configuration (body: `NodeDeviceConfiguration` JSON). Returns the id. | UI |
| GET | `/api/nodes/{id}/devices/status` | Device states, fetched from the node | UI |
| GET | `/api/nodes/{id}/device/templates` | Device templates, fetched from the online node | UI |
| DELETE | `/api/v2/nodes/{id}` | Deletes a node (Orchestrator 1.4.0). Deprecated alias: `GET /api/nodes/{id}/delete`. | UI (1.2.0) |
| POST | `/api/nodes/checkplugin` | Validate a plugin package URL (`PluginFile`) | UI |
| POST | `/api/nodes/validatecron` | Validate a refresh schedule | UI |
| GET | `/api/nodes/report/templates` | All report templates | UI, InfluxDB connector |
| GET | `/api/nodes/command/templates` | All command templates | UI, InfluxDB connector |
| GET | `/api/nodes/variable/templates` | All variable templates | UI, InfluxDB connector |
| GET | `/api/nodes/report/{id}/state` | Current report state | UI |
| GET | `/api/nodes/command/{id}/state` | Last command state | UI |
| POST | `/api/nodes/report/state` | Set report states (body: `Report[]`) | UI |
| GET | `/api/nodes/variables` | All variables | UI |
| POST | `/api/nodes/variable/save` | Save a variable (`VariableDTO`) | UI |
| DELETE | `/api/v2/variables/{id}` | Deletes a variable (Orchestrator 1.4.0). Deprecated alias: `GET /api/nodes/variable/{id}/delete`. | UI (1.2.0) |

### Reports, commands, variables (used by Elsa)

| Method | Route | Purpose | Main callers |
|---|---|---|---|
| GET | `/api/report/{id}/value` | Current report value | Elsa `RIoTData` |
| GET | `/api/report/templates` | Report templates | Elsa (activity pickers) |
| GET | `/api/command/{id}/value` | Last command value | Elsa `RIoTData` |
| GET | `/api/command/templates` | Command templates | Elsa |
| POST | `/api/command/execute` | Body: `Command`. Queues it like `POST /api/v2/commands` with the default time-to-live (Orchestrator 1.4.0; before, it was published once). Returns `200` once **queued**, `400` when no node owns the command id. | UI, Elsa `RIoTOutput` |
| GET | `/api/variable/{id}/value` | Variable value | Elsa `RIoTData` |
| GET | `/api/variable/templates` | Variable templates | Elsa |

### Dashboard (`api/dashboard`)

| Method | Route | Purpose |
|---|---|---|
| GET | `/api/dashboard/configuration` | Dashboard definition. `?history=true` includes history. |
| POST | `/api/dashboard/configuration` | Save the dashboard |
| GET | `/api/dashboard/reports` | Current report states (UI's initial state load) |
| GET | `/api/dashboard/report/{id}/history` | Report history (only for templates with `maintainHistory`) |
| DELETE | `/api/v2/reports/history` | Clears the report history (Orchestrator 1.4.0). Deprecated alias: `GET /api/dashboard/reports/history/reset`. |

### Matter bridge (`api/matter`)

| Method | Route | Purpose |
|---|---|---|
| GET | `/api/matter/status` | Bridge status |
| GET / POST | `/api/matter/configuration` | Read / save `MatterConfiguration` |
| GET | `/api/matter/qr` | Commissioning QR code (PNG) |
| POST | `/api/v2/matter/commissioning/open` | Opens the commissioning window. Deprecated alias: `GET /api/matter/commissioning/open`. |
| POST | `/api/v2/matter/devices/refresh` | Rebuilds bridged endpoints. Deprecated alias: `GET /api/matter/devices/refresh`. |
| POST | `/api/v2/matter/reset` | Resets the bridge. Deprecated alias: `GET /api/matter/reset`. |

The six v2 routes above replace `GET` routes that changed state (backlog item 7, Orchestrator 1.4.0).
The old routes still work as deprecated aliases: their responses carry `Deprecation: true` and
`Link: <v2 route>; rel="successor-version"`, and the first use of each is logged as a warning. They
are removed in a later release; UI 1.2.0 uses the v2 routes.

### Commands (`CommandsController`, `api/v2/commands`)

Commands with a delivery status ([design 7.1](../design/reliable-delivery.md), Orchestrator 1.4.0).
Every command, from either endpoint, waits in the outbox while its node is offline and expires
after its time-to-live (default `RIOT2_OUTBOX_COMMAND_TTL`, 30 s).

| Method | Route | Purpose |
|---|---|---|
| POST | `/api/v2/commands` | Body: `{ "id", "value", "ttlSeconds"?, "wait"? }`; `ttlSeconds` 1–86400. Returns `202` with a delivery and a `Location` header, or with `"wait": true` `200` once the delivery is final (at the latest at its expiry). `400` for a missing id or value or a bad `ttlSeconds`, `404` when no node owns the command id. |
| GET | `/api/v2/commands/{correlationId}` | The delivery, or `404`. Final deliveries are kept for 24 hours. |

A delivery is `{ correlationId, commandId, nodeId, status, isFinal, error, attempts, created,
expires, updated }`. `status`:

| Status | Meaning | Final |
|---|---|---|
| `pending` | Waiting for the node, for a retry, or for the node's answer | No |
| `executed` | The device ran it without an exception (not a physical confirmation; that is the device's next report) | Yes |
| `failed` | The device threw; `error` says why | Yes |
| `unknownCommand` | No device on the node owns the command | Yes |
| `duplicate` | The node had executed this delivery before (its answer was lost) and didn't run it again; the state is set | Yes |
| `sent` | Published to a node that doesn't report results (no `command-result/1`) | Yes |
| `expired` | The time-to-live passed without an answer | Yes |

A node that advertises `command-result/1` must answer within 5 seconds, or the command is sent
again with the same `correlationId`. A `rejected` answer (queue full, device not ready yet) is
retried too, with backoff. The command's state (`GET /api/command/{id}/value`) is set when the node
answers `executed`, or when the command is sent to a node without results.

### Outbox (`OutboxController`, `api/v2/outbox`)

| Method | Route | Purpose |
|---|---|---|
| GET | `/api/v2/outbox/summary` | Durable delivery state ([design 7.1](../design/reliable-delivery.md), Orchestrator 1.3.0). Body: `{ "counts": { "pending", "sent", "done", "failed", "expired" }, "oldestPending": entry \| null, "lastErrors": [entry] }`, where an entry is `{ id, kind, target, subject, status, attempts, created, expires, updated, ageSeconds, lastError }` (times ISO 8601 UTC; `kind` is `workflow` or `command`; `subject` is the report id or the command id; a command's `target` is its node id). `lastErrors` holds the ten most recently updated rows with an error. Final rows are kept for 24 hours. |

### Health

`GET /health`: ASP.NET health checks, as plain text `Healthy`, `Degraded` or `Unhealthy`.
`mqtt` is unhealthy (503) while the broker is disconnected. `outbox` is `Degraded` (200) when more
than 500 rows (workflow triggers and, from Orchestrator 1.4.0, commands) are pending or one is older
than half its time-to-live (Orchestrator 1.3.0).

## Node (`RIoT2.Net.Node/Program.cs`)

Base: `RIOT2_NODE_URL`, advertised as `nodeBaseUrl`.

| Method | Route | Purpose |
|---|---|---|
| GET | `/api/node/manifest` | Node image `PackageManifest` |
| GET | `/api/node/plugin/manifest` | Installed plugin package `PackageManifest` |
| GET | `/api/device/status` | `DeviceStatus[]` for all devices |
| GET | `/api/device/configuration/templates` | `DeviceConfiguration[]` templates from every loaded plugin |
| GET | `/health` | Health, including the MQTT connection state: unhealthy (503) while the broker is disconnected (Node 1.2.0) |

Plugins can add controllers, because the Node maps controllers from plugin assemblies. The default
catalog (`RIoT2.Net.Devices/Controllers`) adds:

| Method | Route | Purpose |
|---|---|---|
| POST | `/api/webhook/{address}` | Webhook input for the Web device. Body is any JSON, max 64 KiB. `address` matches the report template `address`. |
| GET | `/api/download/{filename}` | Download a stored file or image |
| GET | `/api/download/list/files` | List stored documents |

## Elsa (`RIoT2.Elsa/RIoT2.Elsa.Server`)

Base: `RIOT2_WORKFLOW_URL` (web/Studio), `RIOT2_WORKFLOW_GRPC_URL` (gRPC).

| Method | Route | Purpose |
|---|---|---|
| POST | `/riot/trigger/{id}` | Sends the stimulus for the `RIoTTrigger` activity: starts or resumes workflows for report `id`. Body: report JSON. |
| gRPC | `riot.RIoTTriggerService/Trigger` | Same as above. Served on a dedicated plaintext HTTP/2 listener (port `RIOT2_WORKFLOW_GRPC_PORT`, default 5003). A `message_id` seen in the last ten minutes is answered with `success=true` and not run again (Elsa 1.3.0). Invalid `data` JSON is `InvalidArgument`. |
| GET | `/health`, `/healthz` | `{ "status": "ok" }`, anonymous |
| * | Elsa Workflows API, Studio at `/` (fallback `/_Host`) | Elsa-defined. Elsa Studio has its own login. |

gRPC contract, defined in two files: `RIoT2.Net.Orchestrator/Protos/riot_trigger.proto` and
`RIoT2.Elsa/RIoT2.Elsa.Server/RIoT/Protos/riot.proto`. The package, service, messages and field numbers
must stay identical. Only `option csharp_namespace` differs, and that is intentional (each project's
own namespace):

```proto
package riot;
service RIoTTriggerService { rpc Trigger (TriggerRequest) returns (TriggerResponse); }
message TriggerRequest  { string id = 1; string data = 2; string message_id = 3; }  // report id, report JSON, idempotency key
message TriggerResponse { bool success = 1; }
```

The orchestrator delivers at least once: a trigger is retried with the same `message_id` after a
transient failure, until it expires (`RIOT2_OUTBOX_WORKFLOW_TTL`). `success=false` and
`InvalidArgument` are final: the trigger is marked `failed` and not retried. An empty `message_id`
(an orchestrator before 1.3.0) is never deduplicated. The call's deadline is at most the trigger's
expiry, and Elsa rejects a request that arrives after its deadline with `DeadlineExceeded`.

## InfluxDB connector

`GET /health` and `GET /healthz` only. Configuration comes from environment variables, and
templates are loaded from the orchestrator.

## Firmware (`RIoT2.Ard.Shared`)

- Outbound: `GET {apiBaseUrl}/api/Nodes/{id}/configuration` over HTTP or HTTPS. The response is
  capped at 32 KiB, and retries back off 1, 2, 4, 8, 16, then 30 s. For HTTPS without a configured
  root CA, the firmware falls back to insecure TLS with a warning.
- Outbound: OTA download from the URL in a `system.ota` command.
- Inbound, normal operation: `GET /api/device/configuration/templates` on port 80
  (`ConfigTemplateServer`). It returns the board's view and peripheral templates, so the
  orchestrator and UI can offer them, the same way as the .NET Node.
- Inbound, provisioning SoftAP only: `GET /` (form), `POST /save` (Wi-Fi, MQTT, node id; then
  restart). Any other path redirects to `/` (captive portal).

## UI and Mobile

- The UI calls only orchestrator endpoints (base URL kept in `orchestratorStore`), plus MQTT over
  WebSockets. Route constants are in `RIoT2.UI/src/models/constants.ts`.
- Mobile hosts the dashboard and receives Firebase pushes. It makes no direct REST calls.
