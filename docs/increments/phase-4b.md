# Increments I59 and later: phase 4 (features), continued

Applies to: all repositories. Index, definition of done and rules: [README.md](README.md). Earlier phase 4
increments are in [phase-3-4.md](phase-3-4.md).

## Phase 4: features (continued)

### I59. Voice announcements on Google Cast speakers (S)

- **Scope:** workflows speak on Google Home and other Cast speakers ([google-cast.md](../guides/google-cast.md)):
  - Devices: the Google Cast speaker device (`GoogleCast`, SharpCaster) with the commands `speak`, `playUrl`,
    `setVolume` and `stop`; an announcement volume that is set back afterwards; speech from Google Translate (no key)
    or Google Cloud Text-to-Speech, which the speaker downloads from the node's `GET /api/cast/audio/{token}`
    ([http-api-services.md](../contracts/http-api-services.md)).
  - Elsa: the template `sauna-ready-announcement.json` (Trigger, Threshold, Output to Speak).

  Depends on I45 (async devices with typed options) and I48 (RIoT Threshold). No Core, MQTT or configuration
  contract changes.
- **Done when:**
  - `GoogleCastTests` pass: commands, volume set back also after a failure, both speech engines, the audio cache
    and the endpoint's token check.
  - The template imports (`WorkflowTemplateTests`).
  - The maintainer's speaker says "Sauna is ready" from the published template.
- **Release order:** Devices `3.0.0` (with the Netatmo and Eufy changes already in it), then Elsa (templates only).

### I60. Dashboard and workflow building over MCP (M)

- **Scope:** the amendment to [ADR 0018](../adr/0018-mcp-server-and-remote-ai-access.md):
  - Orchestrator: the `dashboard` tool group (get, card kinds, page and card tools, `save_dashboard`, versions and
    restore), the stored card catalog, dashboard versions with their REST routes, the `riot2/orchestrator/dashboard`
    notice, and `list_workflow_activities` and `get_workflow_activity`
    ([mcp.md](../contracts/mcp.md), [dashboard.md](../contracts/dashboard.md)).
  - UI: uploading the card catalog, the editor's history with restore, reloading on the notice (or asking when
    there are unsaved changes), the `dashboard` group on the AI access page.

  Depends on I56 (card kit) and I57. No Core change: the notice's topic is the orchestrator's own.
- **Done when:**
  - `DashboardMcpTests` pass: the catalog's checks and version rule, versions and restore, the cards' checks
    against the catalog and the templates, and the compact form.
  - `McpEndToEndTests.AnAssistantBuildsADashboardCardAndUndoesIt` passes: an MCP client adds a page and a card,
    a wrong card is refused with a reason, the notices are published, and a restore undoes the card.
  - The UI's catalog, store and access tests pass, and an open dashboard reloads after an assistant's change.
- **Release order:** Orchestrator `1.24.0`, then UI `1.14.0` (the UI uploads its catalog to an orchestrator that
  has the route; an older orchestrator just doesn't get it).
