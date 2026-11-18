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
- **Release order:** Orchestrator `1.25.0`, then UI `1.14.0` (the UI uploads its catalog to an orchestrator that
  has the route; an older orchestrator just doesn't get it).

### I61. Site configuration and installer (M)

- **Scope:** [ADR 0020](../adr/0020-site-configuration-and-installer.md):
  - `deploy/install.sh` and `install.ps1`:
    - install a host from a site folder of plain settings and secret files;
    - compare the installed versions first;
    - back up, export and ask per category before an upgrade;
    - put secret files into volumes with `once` and `managed` rules;
    - restore the configuration while keeping the running Matter pairing;
    - import workflows and Grafana dashboards.

    Their shared logic is `deploy/installer/riot2site.py`. The template is `deploy/site-template/`.
    `install.ps1 -RemoteHost` (`deploy/installer/remote.ps1`) installs on a NAS from the site folder on a PC:
    it copies the host's folder there and runs `install.sh --plain` over SSH.
  - `compose.lan.yml`, `compose.lan.influx.yml` and `compose.lan.observability.yml`: static LAN addresses on an
    external qnet or macvlan network. Grafana's "Site" dashboard folder (`RIOT2_GRAFANA_SITE_DASHBOARDS`).
  - UI: `RIOT2_UI_PORT` ([env-vars.md](../contracts/env-vars.md#ui)).
  - The [site configuration](../guides/site-configuration.md) and
    [static LAN addresses](../guides/static-lan-addresses.md) guides.

  No service code or contract changes besides the UI's variable.
- **Done when:**
  - `installer/test_riot2site.py` passes.
  - `tools/installer-check` passes in `deploy-check.yml`: a fresh install, an up-to-date re-run, the export, a
    reconfiguration, a restore that keeps the Matter pairing, an upgrade, a refused downgrade, `install.ps1`,
    and `install.ps1 -RemoteHost` from a site folder on the "PC".
  - The UI's entrypoint tests pass with `RIOT2_UI_PORT`.
  - The maintainer's QNAP (qnet, static addresses), Raspberry Pi node and M5Dial run from the site folder.
- **Release order:** UI `1.15.0`, then the UI tag in `deploy/`. The installer and the compose files need no
  release; `compose.lan.yml` works with an older UI on port 8080.

### I62. Voice satellites over Wyoming (M)

- **Scope:** [ADR 0022](../adr/0022-voice-satellites.md): an Amazon Echo running echo-dot-assist's hassmic
  (`PROTO=wyoming`) becomes a voice assistant for RIoT2 ([voice-satellite.md](../guides/voice-satellite.md)):
  - Devices: the Voice satellite device (`VoiceSatellite`): a Wyoming client with reconnect and ping, the end of
    speech by level (`EndpointDetector`), speech to text (Wyoming, OpenAI-compatible) and text to speech (Wyoming,
    OpenAI-compatible, Google Cloud); report `state` and `transcript`, commands `speak` and `cancel`; a request
    without an answer ends quietly.
  - Elsa: the template `voice-assistant.json` (Trigger on the transcript, Run LLM with `ReadValues` and
    `SendCommands`, Output to Speak; an apology when the model fails).
  - `deploy/compose.voice.yml`: wyoming-faster-whisper and wyoming-piper, with their variables.

  Depends on I45 (async devices with typed options) and I55 (Run LLM). No Core, MQTT or configuration contract
  changes.
- **Done when:**
  - `VoiceEngineTests` and `VoiceSatelliteTests` pass: the Wyoming framing (UTF-8 text as hassmic reads it), the end
    of speech, WAV, each engine against a stand-in, and the device against a stand-in for hassmic (a request
    reported and answered, nothing said, no answer, cancel, a failing engine, reconnects, invalid parameters).
  - The template imports (`WorkflowTemplateTests`); `deploy-check.yml` validates `compose.voice.yml`.
  - The maintainer's Echo Dot 2 (RS03QR) answers a question about a value and switches a device, in Finnish and in
    English. Check on it whether `speak` plays while the Echo is idle (an announcement).
- **Release order:** Devices `3.1.0` (after `3.0.0` of I59), then Elsa (templates only). `compose.voice.yml` needs
  no release.

### I63. Voice satellites over the ESPHome API (M)

- **Scope:** [ADR 0022](../adr/0022-voice-satellites.md): the Voice satellite device also speaks the ESPHome native
  API (hassmic's default, TCP 26053): Noise encryption with a key the device sets, the protobuf messages of
  `api.proto`, the voice assistant messages, and the Echo's entities as reports and commands (light ring, button
  events, volume, mute, do not disturb, the wake word select, timers, announcements). The reply audio is served by
  the node. Several Echos arbitrate among themselves. The `state`, `transcript`, `speak` and `cancel` ids stay.
  Designed after I62 is released.
- **Done when:** the device's tests pass against a stand-in for hassmic's ESPHome API, and the maintainer's Echo works
  in ESPHome mode with the I62 workflow unchanged.
