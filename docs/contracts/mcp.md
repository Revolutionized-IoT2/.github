# MCP server

Applies to: RIoT2.Net.Orchestrator (`Controllers/McpController.cs`, `Services/Mcp/`) and RIoT2.UI (the AI access page).
The decision is [ADR 0018](../adr/0018-mcp-server-and-remote-ai-access.md); the settings are in
[env-vars.md](env-vars.md#orchestrator), the metrics in [metrics.md](metrics.md), and setting it up in
[remote-ai-access.md](../guides/remote-ai-access.md). The REST conventions of [http-api.md](http-api.md#conventions) apply.

## AI access page (`McpController`, `api/v2/mcp`)

Orchestrator 1.22.0. Reads are Viewer.

| Method | Route | Purpose |
|---|---|---|
| GET | `/api/v2/mcp/status` | `{ enabled, localUrl, remote: { enabled, auth, port, publicUrl, maxRole, subjectsRestricted }, groups: [{ id, role }], tools: [{ name, group, role, write }] }` |
| GET | `/api/v2/mcp/configuration` | The tool policy: `{ id, localEnabled, remoteEnabled, groups, allowedCommands, writesPerMinute }`; the defaults (groups `read`, `health`, `workflows`, no commands, 10 writes) when none is stored |
| PUT | `/api/v2/mcp/configuration` | `{ localEnabled, remoteEnabled, groups, allowedCommands, writesPerMinute }`: known groups, command ids of 1–200 characters (at most 1000), 1–600 writes. The stored policy, or `400 { errors }`. Admin. |
| GET | `/api/v2/mcp/activity` | The latest tool calls since the start, newest first: `[{ time, listener, user, tool, target, outcome, durationMs, error }]`; `outcome` is `ok`, `error`, `denied`, `limited` or `failed`. `?max=100` (1–200). |

## Endpoints

`/mcp` (with `RIOT2_MCP_ENABLED=true`) is an MCP server over Streamable HTTP, stateless: `POST` JSON-RPC
`initialize`, `tools/list` and `tools/call`. It has the `Viewer` policy, as the REST API. With `RIOT2_MCP_AUTH`, a
second port (`RIOT2_MCP_REMOTE_PORT`, default 8090) serves only `/mcp` (and the path of `RIOT2_MCP_PUBLIC_URL`) and
`GET /.well-known/oauth-protected-resource[/...]` (RFC 9728: `{ resource, authorization_servers, bearer_methods_supported,
scopes_supported, resource_name }`); every other path is `404`, and the API port answers `404` for the remote
listener's internal routes. Without a valid token it answers `401` with `WWW-Authenticate: Bearer resource_metadata="…"`
(`oidc`) or `Bearer realm="RIoT2"` (`cloudflare-access`), more than 120 requests a minute per user `429`.

## Tools

By group (the group's role in brackets); a tool is listed and callable only when its group is on, the
listener is on and the caller has the role:

| Group | Tools |
|---|---|
| `read` (Viewer) | `list_values(kind?, query?)` (commands carry `allowed`, forecast reports `forecast`), `read_value(id)`, `read_values(ids)` (1–50), `read_forecast(id, window?, hours?, from?, to?, rank?)` (a `ForecastSummary`, [forecasts.md](forecasts.md)), `list_command_plans(commandId?, activeOnly = true)` (Orchestrator 1.23.0) |
| `health` (Viewer) | `list_nodes`, `get_system_health`, the objects of `/api/nodes` and `/api/v2/system/health` |
| `commands` (Operator) | `send_command(id, value, waitSeconds = 10)` (1–30 s): only `allowedCommands`, through the command outbox; `{ id, correlationId, status, error }`, an error result unless executed, sent, duplicate or pending. `plan_command(id, steps, name?)` (1.23.0): a command plan of `[{ at, value }]` for an allowed command, which replaces its active plan; `{ planId, commandId, name, source, status, createdAt, next, steps }` |
| `variables` (Operator) | `set_variable(id, value)`: the value only, converted to the variable's type, published as a report |
| `workflows` (Viewer) | `list_workflows`, `get_workflow(definitionId, version?)`, `list_workflow_runs(definitionId?, status?, page = 0, pageSize = 20)`, `get_workflow_run(instanceId)`, `list_workflow_activities(category?, kind?, query?)` and `get_workflow_activity(type)` (1.25.0: the designer's activity catalog, `GET /api/v2/workflows/catalog`, with an `example` activity and connection for the definition model) |
| `workflowControl` (Operator) | `cancel_workflow_run(instanceId)` |
| `dashboard` (Admin) | Orchestrator 1.25.0, [below](#dashboard-tools): `get_dashboard(pageId?)`, `list_dashboard_cards(kind?)`, `add_dashboard_page`, `update_dashboard_page`, `remove_dashboard_page`, `add_dashboard_card`, `update_dashboard_card`, `move_dashboard_card`, `remove_dashboard_card`, `save_dashboard(dashboard)`, `list_dashboard_versions`, `restore_dashboard_version(versionId)` |
| `admin` (Admin) | `get_node_configuration(nodeId)` (every device parameter value is `"[redacted]"`), `save_node_configuration(nodeConfiguration)` (`"[redacted]"` keeps the stored value), `save_variable(name, value, id?, description?, isPersistent?)`, `save_workflow(model, definitionId?, publish?)`, `publish_workflow(definitionId)`, `retract_workflow(definitionId)` |

`send_command`, `plan_command`, `set_variable`, `cancel_workflow_run`, the dashboard writes and the admin writes share
`writesPerMinute`. A command that isn't allowed is `denied` before it counts. There are no delete tools (but for
dashboard pages and cards, which a version restores) and none for security, backups, language model connections,
Matter or the MCP policy.

## Dashboard tools

The tools read and write a **compact form** of the dashboard ([dashboard.md](dashboard.md)): pages
`{ id, name, icon, cards }`, cards `{ id, kind, name, icon, size, settings, elements }` (`size` is `small`, `half`,
`large` or `full`; a card saved before card kinds has `kind: null` and its `legacyType`), elements
`{ id, name, icon?, role?, reportId?, commandId?, properties }`. Templates, reports and the legacy `type` are left out;
the orchestrator fills them in.

- **Checks.** A card's kind must be in the [card catalog](dashboard.md#card-catalog-orchestrator-1250) the UI uploaded;
  its settings and element properties must be the kind's, of the right type (numbers in range, a select's options);
  its elements must match the kind's list (count) or slots (`role`, required slots present); report and command ids
  must exist and suit the slot (`required`, `optional`, `none`); a `member` must be in the report's value schema.
  A refused call says what to fix and saves nothing. Warnings (a member chosen for an entity report, a value type
  that doesn't suit the slot) come back in `warnings`.
- **Defaults.** A new card's settings start from its kind's defaults, its size from the kind's, an element's
  properties from its slot's; an element without a name takes its template's.
- **Updates.** `update_dashboard_card` merges `settings` by key (`null` restores the default); `elements`, when given,
  replace the card's (an element that keeps its `id` keeps its properties). `save_dashboard` keeps pages and cards
  whose ids exist, adds the rest with new ids and removes what it leaves out.
- **Results.** Each write returns its result with `versionId` (the dashboard's newest version) and `changed`. Edits
  run one at a time; each saves the dashboard with a summary such as "Added the gauge card 'Battery' to the page
  'Home'", which its version keeps.
- Without a card catalog (no UI 1.14.0 has connected yet) the card tools and `save_dashboard` answer with an error
  that says so; `get_dashboard`, the page tools, moving and removing cards and the versions work.
