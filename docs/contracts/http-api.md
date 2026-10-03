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
- New endpoints must not change state on `GET`. The existing state-changing `GET`s are listed
  below as legacy; don't add more.
- Ports: see [env-vars.md](env-vars.md#ports-volumes-and-images).

## Cross-repository URLs

| URL | Served by | Called by | Constant |
|---|---|---|---|
| `GET /api/nodes/{id}/configuration` | Orchestrator | Node (`NodeConfigurationServiceBase`), firmware (`OrchestratorClient`), UI | `ApiConfigurationUrl` |
| `GET /api/device/configuration/templates` | Node | Orchestrator (`OnlineNodeService`, via `nodeBaseUrl`) | `ApiConfigurationTemplateUrl` |
| `GET /api/device/status` | Node | Orchestrator (`OnlineNodeService`, via `nodeBaseUrl`) | `ApiDeviceStateUrl` |
| `POST /riot/trigger/{id}` | Elsa | Nothing today (the orchestrator uses the gRPC equivalent) | `ApiWorkflowTriggerUrl` |
| gRPC `riot.RIoTTriggerService/Trigger` | Elsa | Orchestrator (`WorkflowTriggerClient`) | `riot_trigger.proto` / `riot.proto` |

## Orchestrator (`RIoT2.Net.Orchestrator/Controllers`)

Base: `RIOT2_ORCHESTRATOR_URL`. CORS allows any origin, method and header.

### Nodes and configuration (`NodesController`, `api/nodes`)

| Method | Route | Purpose | Main callers |
|---|---|---|---|
| GET | `/api/nodes` | All node configurations | UI |
| GET | `/api/nodes/online` | Online nodes (from `NodeOnlineMessage`s) | UI |
| GET | `/api/nodes/{id}/configuration` | Node configuration. `?state=true` appends current states. | Node, firmware, UI |
| POST | `/api/nodes/configuration` | Save a node configuration (body: `NodeDeviceConfiguration` JSON). Returns the id. | UI |
| GET | `/api/nodes/{id}/devices/status` | Device states, fetched from the node | UI |
| GET | `/api/nodes/{id}/device/templates` | Device templates, fetched from the online node | UI |
| GET | `/api/nodes/{id}/delete` | **Legacy state-changing GET.** Deletes a node. | UI |
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
| GET | `/api/nodes/variable/{id}/delete` | **Legacy state-changing GET.** Deletes a variable. | UI |

### Reports, commands, variables (used by Elsa)

| Method | Route | Purpose | Main callers |
|---|---|---|---|
| GET | `/api/report/{id}/value` | Current report value | Elsa `RIoTData` |
| GET | `/api/report/templates` | Report templates | Elsa (activity pickers) |
| GET | `/api/command/{id}/value` | Last command value | Elsa `RIoTData` |
| GET | `/api/command/templates` | Command templates | Elsa |
| POST | `/api/command/execute` | Body: `Command`. Publishes to `riot2/node/{owner}/command` and sets the command state. Returns `200` once **published**, not executed. | UI, Elsa `RIoTOutput` |
| GET | `/api/variable/{id}/value` | Variable value | Elsa `RIoTData` |
| GET | `/api/variable/templates` | Variable templates | Elsa |

### Dashboard (`api/dashboard`)

| Method | Route | Purpose |
|---|---|---|
| GET | `/api/dashboard/configuration` | Dashboard definition. `?history=true` includes history. |
| POST | `/api/dashboard/configuration` | Save the dashboard |
| GET | `/api/dashboard/reports` | Current report states (UI's initial state load) |
| GET | `/api/dashboard/report/{id}/history` | Report history (only for templates with `maintainHistory`) |
| GET | `/api/dashboard/reports/history/reset` | **Legacy state-changing GET.** Clears history. |

### Matter bridge (`api/matter`)

| Method | Route | Purpose |
|---|---|---|
| GET | `/api/matter/status` | Bridge status |
| GET / POST | `/api/matter/configuration` | Read / save `MatterConfiguration` |
| GET | `/api/matter/qr` | Commissioning QR code (PNG) |
| GET | `/api/matter/commissioning/open` | **Legacy state-changing GET.** Opens the commissioning window. |
| GET | `/api/matter/devices/refresh` | **Legacy state-changing GET.** Rebuilds bridged endpoints. |
| GET | `/api/matter/reset` | **Legacy state-changing GET.** Resets the bridge. |

### Health

`GET /health`: ASP.NET health checks, including the MQTT connection state.

## Node (`RIoT2.Net.Node/Program.cs`)

Base: `RIOT2_NODE_URL`, advertised as `nodeBaseUrl`.

| Method | Route | Purpose |
|---|---|---|
| GET | `/api/node/manifest` | Node image `PackageManifest` |
| GET | `/api/node/plugin/manifest` | Installed plugin package `PackageManifest` |
| GET | `/api/device/status` | `DeviceStatus[]` for all devices |
| GET | `/api/device/configuration/templates` | `DeviceConfiguration[]` templates from every loaded plugin |
| GET | `/health` | Health |

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
| gRPC | `riot.RIoTTriggerService/Trigger` | Same as above. Served on a dedicated plaintext HTTP/2 listener (port `RIOT2_WORKFLOW_GRPC_PORT`, default 5003). |
| GET | `/health`, `/healthz` | `{ "status": "ok" }`, anonymous |
| * | Elsa Workflows API, Studio at `/` (fallback `/_Host`) | Elsa-defined. Elsa Studio has its own login. |

gRPC contract (identical in `RIoT2.Net.Orchestrator/Protos/riot_trigger.proto` and
`RIoT2.Elsa/RIoT2.Elsa.Server/RIoT/Protos/riot.proto`; keep them in sync):

```proto
package riot;
service RIoTTriggerService { rpc Trigger (TriggerRequest) returns (TriggerResponse); }
message TriggerRequest  { string id = 1; string data = 2; }  // report id, report JSON
message TriggerResponse { bool success = 1; }
```

## InfluxDB connector

`GET /health` and `GET /healthz` only. Configuration comes from environment variables, and
templates are loaded from the orchestrator.

## Firmware (`RIoT2.Ard.Shared`)

- Outbound: `GET {apiBaseUrl}/api/Nodes/{id}/configuration` over HTTP or HTTPS. The response is
  capped at 32 KiB, and retries back off 1, 2, 4, 8, 16, then 30 s. For HTTPS without a configured
  root CA, the firmware falls back to insecure TLS with a warning.
- Outbound: OTA download from the URL in a `system.ota` command.
- Inbound, provisioning SoftAP only: `GET /` (form), `POST /save` (Wi-Fi, MQTT, node id; then
  restart). Any other path redirects to `/` (captive portal).

## UI and Mobile

- The UI calls only orchestrator endpoints (base URL kept in `orchestratorStore`), plus MQTT over
  WebSockets. Route constants are in `RIoT2.UI/src/models/constants.ts`.
- Mobile hosts the dashboard and receives Firebase pushes. It makes no direct REST calls.

## Planned (not implemented)

From PLATFORM-REVIEW design 7.1: `POST /api/v2/commands`, `GET /api/v2/commands/{correlationId}`
and `GET /api/v2/outbox/summary`. The existing `POST /api/command/execute` stays unchanged.
