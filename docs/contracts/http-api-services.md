# HTTP and gRPC APIs: node, Elsa, connector, UI

Applies to: Node and device plugins, Elsa, InfluxDB connector, UI, Mobile. The orchestrator's
routes, the conventions and the firmware are in [http-api.md](http-api.md); the docs check reads
both files.

## Node (`RIoT2.Net.Node/Program.cs`)

Base: `RIOT2_NODE_URL`, advertised as `nodeBaseUrl`.

| Method | Route | Purpose |
|---|---|---|
| GET | `/api/node/manifest` | Node image `PackageManifest` |
| GET | `/api/node/plugin/manifest` | Installed plugin package `PackageManifest` |
| GET | `/api/device/status` | `DeviceStatus[]` for all devices |
| GET | `/api/device/configuration/templates` | `DeviceConfiguration[]` templates of the loaded plugins, with `parameterDefinitions` |
| GET | `/health` | Health: unhealthy (503) while the broker is disconnected |

Its routes are `Viewer`. The Node also maps controllers from plugin assemblies; an action without
a policy gets `Viewer` for `GET`, otherwise `Operator`. The default catalog
(`RIoT2.Net.Devices/Controllers`) adds:

| Method | Route | Purpose |
|---|---|---|
| POST | `/api/webhook/{address}` | Webhook input for the Web device (any JSON, max 64 KiB); `address` is the report template's. |
| GET | `/api/download/{filename}` | Download a stored file or image |
| GET | `/api/download/list/files` | List stored documents |

## Elsa (`RIoT2.Elsa/RIoT2.Elsa.Server`)

The separate workflow host, used when the orchestrator has `RIOT2_WORKFLOW_MODE=remote`
([ADR 0016](../adr/0016-integrated-workflows-and-llm.md)). Base: `RIOT2_WORKFLOW_URL` (web),
`RIOT2_WORKFLOW_GRPC_URL` (gRPC).

| Method | Route | Purpose |
|---|---|---|
| POST | `/riot/trigger/{id}` | Sends the stimulus for the `RIoTTrigger` activity: starts or resumes workflows for report `id`. Body: report JSON. Operator (like gRPC). |
| gRPC | `riot.RIoTTriggerService/Trigger` | Same, on a plaintext HTTP/2 listener (`RIOT2_WORKFLOW_GRPC_PORT`, default 5003). A `message_id` seen in the last ten minutes gets `success=true` and isn't run again. Invalid `data` JSON is `InvalidArgument`. |
| * | `/riot/workflows`, `/riot/workflows/catalog`, `/riot/workflows/runs`, `/riot/workflows/runs/{instanceId}`, `/riot/workflows/runs/{instanceId}/cancel`, `/riot/workflows/import`, `/riot/workflows/{definitionId}`, `/riot/workflows/{definitionId}/versions`, `/riot/workflows/{definitionId}/export`, `/riot/workflows/{definitionId}/publish`, `/riot/workflows/{definitionId}/retract` | The workflow management API (Elsa 2.0.0): the same methods, bodies and policies as the orchestrator's [`/api/workflows`](http-api.md#workflows-workflowscontroller-apiworkflows), without `status` and `templates`. Only the orchestrator calls it. |
| GET | `/health`, `/healthz` | `{ "status": "ok" }`, anonymous |
| * | `/api/workflows/*` | Elsa's HTTP endpoint activities (`Http__BasePath`). In the embedded mode they're at `/workflows/*` on the orchestrator's port. |

Elsa 2.0.0 has no Studio, no Elsa Workflows API and no login. A Run LLM step calls the
orchestrator's `POST /api/llm/run`, at the URL in the configuration command.

gRPC contract, defined in two files: `RIoT2.Net.Orchestrator/Protos/riot_trigger.proto` and
`RIoT2.Elsa/RIoT2.Elsa.Server/RIoT/Protos/riot.proto`. The package, service, messages and field numbers
must stay identical; only `option csharp_namespace` differs, intentionally:

```proto
package riot;
service RIoTTriggerService { rpc Trigger (TriggerRequest) returns (TriggerResponse); }
message TriggerRequest  { string id = 1; string data = 2; string message_id = 3; }  // report id, report JSON, idempotency key
message TriggerResponse { bool success = 1; }
```

Delivery is at least once: a transient failure is retried with the same `message_id` until the
trigger expires (`RIOT2_OUTBOX_WORKFLOW_TTL`); `success=false` and `InvalidArgument` are final. An
empty `message_id` is never deduplicated. The deadline is at most the trigger's expiry.

## InfluxDB connector

Configuration comes from environment variables, and templates are loaded from the orchestrator.
Both routes are anonymous. They come from the connector SDK, so every connector has them.

| Method | Route | Purpose |
|---|---|---|
| GET | `/health` | `{ "status", "mqtt", "sink", "queue", "spool": { "enabled", "messages", "bytes", "maxBytes" } }` (1.9.0). `status` is `unhealthy` (HTTP 503) while MQTT is disconnected, `degraded` while InfluxDB doesn't answer its ping (5 s) or messages wait in the spool, otherwise `ok`. |
| GET | `/healthz` | `{ "status": "ok" }`: the process is running |

With `RIOT2_CONNECTOR_URL` set, a connector announces that URL, and the orchestrator reads its
`/health` for `GET /api/v2/connectors` and the UI.

## Prometheus exporter (`RIoT2.Connector.Prometheus`)

`/health` and `/healthz` as above (the sink is always healthy: Prometheus pulls), and:

| Method | Route | Purpose |
|---|---|---|
| GET | `/metrics` | The latest report (and command) values in the Prometheus text format 0.0.4 ([metrics.md](metrics.md#prometheus-exporter)). Viewer; anyone while the security mode is `off`. |

## Home Assistant connector (`RIoT2.Connector.HomeAssistant`)

`/health` and `/healthz` as above; the sink is healthy while the connector is connected to Home
Assistant's broker. It calls the orchestrator's template routes and `POST /api/v2/commands`
([http-api.md](http-api.md)).

## UI and Mobile

- The UI calls only orchestrator endpoints, plus MQTT over WebSockets. From UI 1.7.0 it reads
  `/api/security/info` on its own origin first; when that answers, it calls the API there (the
  image's `/api` proxy), otherwise at the configuration command's `apiBaseUrl`. Route constants are in `RIoT2.UI/src/models/constants.ts`.
- Mobile hosts the dashboard and receives Firebase pushes. It makes no direct REST calls.
