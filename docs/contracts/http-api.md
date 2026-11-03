# HTTP and gRPC APIs

Applies to: Orchestrator, Node and device plugins, Elsa, InfluxDB connector, firmware, UI.
Source of truth: controller attributes and `Map*` calls in each repository's code. URLs shared
across repositories are constants in `RIoT2.Core/src/Contracts/Constants.cs`.
Nothing is enforced by default ([ADR 0002](../adr/0002-isolated-network-security-model.md)), but
every endpoint has a policy for the optional security mode ([design 7.5](../design/security-mode.md)).

## Conventions

- JSON is camelCase. Enums are serialized as numbers.
- There is no other casing: the `json-naming-policy` request header, deprecated since Orchestrator
  1.11.0, is ignored since 1.19.0 ([I45](../increments/phase-3-4.md#i45-core-20-remove-compatibility-layers-m)).
- Responses written with `Json.Serialize` (for example the node configuration) also camel-case
  **dictionary keys**. This affects `deviceParameters`; see [configuration.md](configuration.md).
- Every service container exposes `GET /health`. Elsa and the connector also expose `/healthz`.
- Policies (I34): `Viewer` for reads, `Operator` for commands and triggers, `Admin` for
  configuration, node, variable, dashboard and Matter writes and backups. `/health` and
  `/api/security/info` are anonymous; a test fails on an endpoint without either. While
  `RIOT2_SECURITY_MODE` is `off` (the only mode yet) every request passes as `local-admin`.
- Service-to-service calls carry `X-RIoT2-Key` when the caller has `RIOT2_API_KEY`; unchecked while `off`.
- The orchestrator's routes are also written to
  [openapi/riot2-orchestrator.json](https://github.com/Revolutionized-IoT2/RIoT2.Net.Orchestrator/blob/main/openapi/riot2-orchestrator.json)
  by every build; the UI tests fail on a route or method that isn't in it. Bodies written with
  `Json.Serialize` have no schema there; their formats are the golden files in
  [RIoT2.Core/contracts/golden/http](https://github.com/Revolutionized-IoT2/RIoT2.Core/blob/main/contracts/golden/README.md).
- New endpoints must not change state on `GET`; the existing ones below are legacy aliases.
- Ports: see [images.md](images.md).

## Cross-repository URLs

| URL | Served by | Called by | Constant |
|---|---|---|---|
| `GET /api/nodes/{id}/configuration` | Orchestrator | Node (`NodeConfigurationServiceBase`), firmware (`OrchestratorClient`), UI | `ApiConfigurationUrl` |
| `GET /api/device/configuration/templates` | Node; firmware (`ConfigTemplateServer`, port 80) | Orchestrator (`OnlineNodeService`, via `nodeBaseUrl`) | `ApiConfigurationTemplateUrl` |
| `GET /api/device/status` | Node | Orchestrator (`OnlineNodeService`, via `nodeBaseUrl`) | `ApiDeviceStateUrl` |
| `POST /riot/trigger/{id}` | Elsa | Nothing today (the orchestrator uses the gRPC equivalent) | `ApiWorkflowTriggerUrl` |
| gRPC `riot.RIoTTriggerService/Trigger` | Elsa | Orchestrator (`ElsaAutomationProvider`, through the outbox) | `riot_trigger.proto` / `riot.proto` |

## Orchestrator (`RIoT2.Net.Orchestrator/Controllers`)

Base: `RIOT2_ORCHESTRATOR_URL`, or the UI's origin through its `/api` proxy. CORS allows any
origin while the mode is `off`. Controllers are `Viewer` unless a row says otherwise.

### Nodes and configuration (`api/nodes`)

| Method | Route | Purpose | Main callers |
|---|---|---|---|
| GET | `/api/nodes` | Every configured node: online state, device states (from the node), manifests, and the sync fields of `/api/v2/nodes/sync` ([configuration.md](configuration.md#desired-state)) | UI |
| GET | `/api/v2/nodes/sync` | Every configured node's sync without asking the nodes (Orchestrator 1.16.0): `{ id, name, isOnline, pluginManifest, desiredRevision, appliedRevision, syncState, configurationState, lastError, failedDevices }`; `configurationState` is the node's last reported state | UI (polls) |
| POST | `/api/v2/nodes/{id}/configuration/apply` | Re-apply: sends the node its configuration command again. `202`; `404` unknown node; `409` offline (it gets the configuration when it comes online). Operator. | UI |
| GET | `/api/nodes/online` | Online nodes, connectors included (`nodeType` 4) | UI |
| GET | `/api/v2/connectors` | Online connectors (Orchestrator 1.17.0): `{ id, name, nodeBaseUrl, manifest, health, healthError }`. `health` is the connector's own `/health` body (also with 503), read when it announced `nodeBaseUrl` (8 s each, in parallel); `healthError` says why it is missing. | UI (polls) |
| GET | `/api/nodes/{id}/configuration` | Node configuration, with `revision` and `hash`. The `ETag` is the hash; a matching `If-None-Match` gets `304`. `?state=true` returns a copy with each command template's last value as `model`, without an `ETag`. | Node, firmware, UI |
| POST | `/api/nodes/configuration` | Save a node configuration (body: `NodeDeviceConfiguration` JSON). Returns the id. Admin. | UI |
| GET | `/api/nodes/{id}/devices/status` | Device states, fetched from the node | UI |
| GET | `/api/nodes/{id}/device/templates` | Device templates, fetched from the online node | UI |
| DELETE | `/api/v2/nodes/{id}` | Deletes a node. Admin. Deprecated alias: `GET /api/nodes/{id}/delete`. | UI |
| POST | `/api/nodes/checkplugin` | Validate a plugin package URL (`PluginFile`) | UI |
| POST | `/api/nodes/validatecron` | Validate a refresh schedule | UI |
| GET | `/api/nodes/report/templates` | All report templates | UI, connectors |
| GET | `/api/nodes/command/templates` | All command templates | UI, connectors |
| GET | `/api/nodes/variable/templates` | All variable templates | UI, connectors |
| GET | `/api/nodes/report/{id}/state` | Current report state | UI |
| GET | `/api/nodes/command/{id}/state` | Last command state | UI |
| POST | `/api/nodes/report/state` | Set report states (body: `Report[]`) | UI |
| GET | `/api/nodes/variables` | All variables | UI |
| POST | `/api/nodes/variable/save` | Save a variable (`VariableDTO`) | UI |
| DELETE | `/api/v2/variables/{id}` | Deletes a variable. Deprecated alias: `GET /api/nodes/variable/{id}/delete`. | UI |

### Reports, commands, variables (used by Elsa)

| Method | Route | Purpose | Main callers |
|---|---|---|---|
| GET | `/api/report/{id}/value` | Current report value | Elsa `RIoTData` |
| GET | `/api/report/templates` | Report templates | Elsa (activity pickers) |
| GET | `/api/command/{id}/value` | Last command value | Elsa `RIoTData` |
| GET | `/api/command/templates` | Command templates | Elsa |
| POST | `/api/command/execute` | Body: `Command`. Queues it like `POST /api/v2/commands` with the default time-to-live. Returns `200` once **queued**, `400` when no node owns the command id. Operator. | UI, Elsa `RIoTOutput` |
| GET | `/api/variable/{id}/value` | Variable value | Elsa `RIoTData` |
| GET | `/api/variable/templates` | Variable templates | Elsa |

Both prefixes list the same templates, with each template's `schema` when the device declares one (Core 2.2.0,
[dashboard.md](dashboard.md#value-schema)). Golden files: `http/templates-*.json`.

### Dashboard (`api/dashboard`)

| Method | Route | Purpose |
|---|---|---|
| GET | `/api/dashboard/configuration` | Dashboard definition ([dashboard.md](dashboard.md)); every page, card and element has an `id`. `?history=true` includes history. |
| POST | `/api/dashboard/configuration` | Save the dashboard; ids are kept, missing ones created |
| GET | `/api/dashboard/reports` | Current report states (UI's initial state load) |
| GET | `/api/dashboard/report/{id}/history` | Report history (only for templates with `maintainHistory`) |
| DELETE | `/api/v2/reports/history` | Clears the report history. Deprecated alias: `GET /api/dashboard/reports/history/reset`. |

### Matter bridge (`api/matter`)

| Method | Route | Purpose |
|---|---|---|
| GET | `/api/matter/status` | Bridge status |
| GET / POST | `/api/matter/configuration` | Read / save `MatterConfiguration` |
| GET | `/api/matter/qr` | Commissioning QR code (PNG) |
| POST | `/api/v2/matter/commissioning/open` | Opens the commissioning window. Deprecated alias: `GET /api/matter/commissioning/open`. |
| POST | `/api/v2/matter/devices/refresh` | Rebuilds bridged endpoints. Deprecated alias: `GET /api/matter/devices/refresh`. |
| POST | `/api/v2/matter/reset` | Resets the bridge. Deprecated alias: `GET /api/matter/reset`. |

Writes on the dashboard and Matter routes are Admin; so is the QR code (it pairs the bridge). The
six v2 routes replace state-changing `GET`s (backlog item 7); the old ones remain deprecated
aliases (`Deprecation: true`, a `Link` to the successor, a warning on first use).

### Commands (`CommandsController`, `api/v2/commands`)

Commands with a delivery status ([design 7.1](../design/reliable-delivery.md)); `POST` is Operator.
Every command waits in the outbox while its node is offline and expires
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
| `executed` | The device ran it without an exception (not a physical confirmation) | Yes |
| `failed` | The device threw; `error` says why | Yes |
| `unknownCommand` | No device on the node owns the command | Yes |
| `duplicate` | The node ran this delivery before (its answer was lost) and didn't run it again | Yes |
| `sent` | Published to a node that doesn't report results (no `command-result/1`) | Yes |
| `expired` | The time-to-live passed without an answer | Yes |

A node with `command-result/1` must answer within 5 s, or the command is resent with the same
`correlationId`; `rejected` is retried with backoff. The command's state is set on `executed`, or
when it is sent to a node without results.

### Outbox (`OutboxController`, `api/v2/outbox`)

| Method | Route | Purpose |
|---|---|---|
| GET | `/api/v2/system/health` | The System page (Orchestrator 1.20.0, [I46](../increments/phase-3-4.md#i46-system-health-page-m)): `{ generatedAt, orchestrator: { version, started, status, checks: [{ name, status, description }] }, outbox: <outbox summary>, nodes: [node] }`. A node is `{ id, name, nodeType, configured, isOnline, since, version, pluginVersion, syncState, configurationState, lastError, history: [{ at, isOnline }], devices: [{ id, name, state, message, lastError, lastErrorAt }] \| null, devicesUnavailable }`; no dashboards. History and last errors are kept in memory since the orchestrator started. Asks each online device node for its device states (5 s each). |
| GET | `/api/v2/outbox/summary` | Durable delivery state ([design 7.1](../design/reliable-delivery.md)): `{ "counts": { "pending", "sent", "done", "failed", "expired" }, "oldestPending": entry \| null, "lastErrors": [entry] }`. An entry is `{ id, kind, target, subject, status, attempts, created, expires, updated, ageSeconds, lastError }` (UTC; `kind` `workflow` or `command`). `lastErrors`: the ten latest rows with an error. |

### Backup (`BackupController`, `api/v2`)

Configuration backup and restore ([design 7.4](../design/operations-as-built.md#as-built-phase-3-i21),
Orchestrator 1.7.0). The zip format: [backup-and-restore.md](../guides/backup-and-restore.md).

| Method | Route | Purpose |
|---|---|---|
| POST | `/api/v2/backup` | Returns a new backup (`application/zip`) |
| POST | `/api/v2/restore` | Body: a backup (`application/zip`, at most 64 MB). Saves the configuration it replaces to `Backups/`, restores, and returns a summary with that `safetyBackup`. `400` (problem details with `errors`) changes nothing; `409`: another backup or restore runs. |
| GET | `/api/v2/backups` | `{ schedule, retention, nextRunAt, lastRun: { at, name, error }, backups: [{ name, sizeBytes, createdAt }] }`, newest first |
| GET | `/api/v2/backups/{name}` | Downloads a backup from `Backups/` |
| POST | `/api/v2/backups/{name}/restore` | Restores a backup from `Backups/`, as above |

### Workflows (`WorkflowsController`, `api/workflows`)

The workflow designer's API ([ADR 0016](../adr/0016-integrated-workflows-and-llm.md), Orchestrator 1.21.0).
It answers the same in both workflow modes: from Elsa in process (`embedded`), or forwarded to the
online workflow host's `/riot/workflows` (`remote`). `503` (problem details) means the remote host is
offline. A workflow is Elsa's definition model JSON (`model`), the format of an Elsa export. Saves
answer `{ succeeded, workflow, errors }`, which is `400` when `succeeded` is false.

| Method | Route | Purpose |
|---|---|---|
| GET | `/api/workflows` | `[{ definitionId, name, description, latestVersion, publishedVersion, isReadonly, updatedAt }]` |
| GET | `/api/workflows/status` | `{ mode, available, engine, host }`: `embedded` or `remote`, and whether the engine answers |
| GET | `/api/workflows/catalog` | The activities the designer offers: type, category, kind, inputs (with UI hints), outputs and outcomes |
| GET | `/api/workflows/templates` | Templates for a RIoT selector, `?types=Report,Command,Variable` (default all); `400` on an unknown type |
| GET | `/api/workflows/runs` | `{ items, totalCount, page, pageSize }`, newest first; `?definitionId=&status=&page=0&pageSize=25` (1–100) |
| GET | `/api/workflows/runs/{instanceId}` | `{ run, activities, incidents }`: each executed activity with its status, outcomes and error |
| POST | `/api/workflows/runs/{instanceId}/cancel` | Cancels a run; `204`/`404`. Operator. |
| POST | `/api/workflows` | Creates a workflow: `{ model, publish }`. Admin. |
| POST | `/api/workflows/import` | Imports an Elsa export or a template from RIoT2.Elsa's `templates/`: `{ model, publish }`. Admin. |
| GET | `/api/workflows/{definitionId}` | The latest version with its `model`, or `?version=` |
| GET | `/api/workflows/{definitionId}/versions` | `[{ id, version, isLatest, isPublished, createdAt }]` |
| GET | `/api/workflows/{definitionId}/export` | `{ fileName, model }` |
| PUT | `/api/workflows/{definitionId}` | Saves the draft (a new version when the latest is published): `{ model, publish }`. Admin. |
| POST | `/api/workflows/{definitionId}/publish` | Publishes the latest version. Admin. |
| POST | `/api/workflows/{definitionId}/retract` | Unpublishes, so the triggers stop; `204`/`404`. Admin. |
| DELETE | `/api/workflows/{definitionId}` | Deletes every version; `204`/`404`. Admin. |

### Language models (`LlmController`, `api/llm`)

The *Run LLM* step's connections and runs (ADR 0016, Orchestrator 1.21.0). API keys are stored
encrypted and never returned.

| Method | Route | Purpose |
|---|---|---|
| GET | `/api/llm/connections` | `[{ id, name, description, provider, endpoint, model, apiVersion, hasApiKey, temperature, maxOutputTokens, enabled }]`; `provider` is `OpenAI`, `AzureOpenAI`, `Anthropic` or `OpenAICompatible` |
| POST | `/api/llm/connections` | Creates one: the fields above with `apiKey` instead of `hasApiKey`. `400 { errors }`. Admin. |
| PUT | `/api/llm/connections/{id}` | Changes one; `apiKey` null keeps the stored key, `""` removes it. Admin. |
| DELETE | `/api/llm/connections/{id}` | `204`/`404`. Admin. |
| POST | `/api/llm/connections/{id}/test` | Asks the model for a one-word answer; the run result. Admin. |
| POST | `/api/llm/run` | Runs a step: `{ connection, instructions, input, responseFormat, jsonSchema, tools, allowedCommands, maxCommands, maxToolCalls, timeoutSeconds, workflowDefinitionId, workflowInstanceId, activityId }`. `200` or `422` with `{ succeeded, text, json, commands, toolCalls, usage, errorCode, error }`. The remote workflow host calls it. Operator. |
| GET | `/api/llm/usage` | `{ from, connections, days, recent }`: runs, failures and tokens per connection and per day, and the latest runs; `?days=30` (1–90) and `?connection=` |

### MCP server (`McpController`, `api/v2/mcp`, and `/mcp`)

The AI access page's routes (`GET /api/v2/mcp/status`, `GET /api/v2/mcp/configuration`, `PUT /api/v2/mcp/configuration`
(Admin), `GET /api/v2/mcp/activity`), the MCP endpoint `/mcp`, the remote listener and the tools are in [mcp.md](mcp.md)
(Orchestrator 1.22.0).

### Security and health

`GET /api/security/info` (anonymous, Orchestrator 1.15.0): `{ "mode": "off", "features": [],
"loginRequired": false, "realtime": "mqtt" }` (`SecurityInfo`, golden file `http/security-info.json`).

`GET /health`: ASP.NET health checks, as plain text `Healthy`, `Degraded` or `Unhealthy`.
`mqtt` is unhealthy (503) while the broker is disconnected. `outbox` is `Degraded` (200) when more
than 500 rows are pending or one is older than half its time-to-live.

## Node, Elsa, connector, UI

The routes of the .NET node and its plugins, Elsa (HTTP and gRPC), the InfluxDB connector, the UI
and Mobile are in [http-api-services.md](http-api-services.md).

## Firmware (`RIoT2.Ard.Shared`)

- Outbound: `GET {apiBaseUrl}/api/nodes/{id}/configuration` over HTTP or HTTPS, with
  `If-None-Match` set to the hash it runs; a matching `hash` in the command skips it. The response is
  capped at 32 KiB; retries back off 1–30 s. HTTPS without a root CA falls back to insecure TLS.
- Outbound: OTA download from the URL in a `system.ota` command.
- Inbound, normal operation: `GET /api/device/configuration/templates` on port 80
  (`ConfigTemplateServer`). It returns the board's view and peripheral templates, so the
  orchestrator and UI can offer them, the same way as the .NET Node.
- Inbound, provisioning SoftAP only: `GET /` (form), `POST /save` (then restart); any other
  path redirects to `/`.
