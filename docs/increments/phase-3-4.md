# Increments I35–I48 and I55: phase 3 (extensibility) and phase 4 (features)

Applies to: all repositories. Index, definition of done and rules: [README.md](README.md).
Snapshot 2026-10-12; verify the scope against the code before starting.

## Phase 3: extensibility

### I35. Verified plugin updates (M)

- **Scope:** [7.2](../design/desired-state-configuration.md) phase 4 on the node, backlog item 5.
  Uses the `coreVersion` rule from the [decisions to confirm](README.md#decisions-to-confirm).
- **Done when:** the node verifies the `.sha256` sidecar, rejects an incompatible `coreVersion`
  without touching `Plugins/`, installs through `Plugins.new/` and `Plugins.previous/`, rolls back
  once when loading fails (no restart loop), and reports `pendingRestart` or `failed`.
- **Done 2026-11-02.** Core `1.19.0` (`PluginPackageInstaller`), Node `1.14.0`. The swap runs at
  the next start, moving folder contents because `/app/Plugins` is a bind mount; a refused package
  is remembered in `Data/plugins.rejected.json`, and the devices still apply with the installed
  plugins ([as built](../design/desired-state-as-built.md#as-built-phase-4-i35)).

### I36. Sync and command status in the UI (M)

- **Scope:** [7.1](../design/reliable-delivery.md) phase 4 and 7.2 phase 6: sync badge, revisions,
  last error, plugin version and "re-apply" per node; command status indicator; outbox view; the
  Elsa "command with confirmation" activity (`wait:true`). Release: Elsa → UI.
- **Done when:** a changed configuration shows "applying" then "in sync", a failing command shows
  `failed` in the UI, and the Elsa activity waits for the result. Nodes without the capability
  show "legacy".
- **Done 2026-11-02.** Orchestrator `1.16.0` (`GET /api/v2/nodes/sync`, re-apply), Elsa `1.9.0`
  ("RIoT Command with confirmation"), UI `1.8.0` (sync badge, re-apply, command status, delivery
  queue). The UI polls the new sync route; the outbox view is a dialog until the health page (I46)
  ([7.1](../design/reliable-delivery-as-built.md#as-built-phase-4-i36),
  [7.2](../design/desired-state-as-built.md#as-built-phase-6-i36)).

### I37. Connector SDK (M)

- **Scope:** [7.3](../design/connector-sdk.md) phase 1 ([ADR 0009](../adr/0009-connector-sdk.md)).
  Release: Core (`RIoT2.Connector.Sdk`) → Influx.
- **Done when:** the Influx connector uses the SDK, and the line protocol it writes for the golden
  messages is identical before and after.
- **Done 2026-11-02.** Core `1.20.0` (`RIoT2.Connector.Sdk`), connector `1.8.0`. Batching (100 or
  1 s) and retry with backoff are in; failed batches are no longer dropped while the target is
  down, and reports that arrive before the templates wait for them
  ([as built](../design/connector-sdk-as-built.md#as-built-phase-1-i37)).

### I38. Connector spool (M)

- **Scope:** 7.3 phase 2. Completes backlog item 2 (the Influx part).
- **Done when:** an InfluxDB outage within the spool limits loses no data, rejected batches go to
  the dead-letter file, shutdown drains to disk, and `/health` and the metrics show spool usage.
- **Done 2026-11-02.** Core `1.21.0`, connector `1.9.0` (new volume `/app/Data`). Messages move to
  disk at the first failure and are written in order once InfluxDB is back; a restart resumes from
  the checkpoint; backlog item 2 is closed. The memory queue's high-water mark (80 %) sends new
  messages to the spool ([as built](../design/connector-sdk-as-built.md#as-built-phase-2-i38)).

### I39. Connectors in the UI and a Prometheus exporter (M)

- **Scope:** 7.3 phase 3 (`NodeType.Connector`, UI connector list) and the Prometheus exporter
  from phase 4.
- **Done when:** connectors are listed separately in the UI, and the Prometheus exporter is
  released and scraped by the observability profile.
- **Done 2026-11-02.** Core `1.22.0` (`NodeType.Connector`, presence with name, URL and version),
  Orchestrator `1.17.0` (`GET /api/v2/connectors` with each connector's health), UI `1.9.0` (connector
  list), InfluxDB connector `1.10.0`, and the new repository `RIoT2.Connector.Prometheus` `1.0.0`
  (`riot2_value` at `/metrics`, job `riot2-values`, dashboard "RIoT2 values")
  ([as built](../design/connector-sdk-as-built.md#as-built-phases-3-and-4-i39)).

### I40. Nightly compose smoke test (S)

- **Scope:** [7.4](../design/operations.md) phase 5 and [M7](../plans/m07-contract-integration-tests.md) step 5.
- **Done when:** a nightly workflow starts the released compose stack, polls every `/health`
  endpoint, and reports failures.
- **Done 2026-11-02.** `nightly-smoke.yml` with `tools/compose-smoke` (`env.sh`, `health.py`): the full
  stack, every health endpoint and both connectors within 2 minutes; a failure opens a `nightly-smoke`
  issue that the next good run closes ([as built](../design/operations-as-built.md#as-built-phase-5-i40)).

### I41. Async-first plugins and the plugin template (M)

- **Scope:** [M12](../plans/m12-device-plugin-sdk.md) steps 5–6.
- **Done when:** `AsyncDeviceBase` no longer blocks, the host uses only async device calls, and
  `dotnet new riot2-plugin` produces a plugin that builds, packs, passes conformance and loads in
  the node.
- **Done 2026-11-02.** Core `1.23.0` (`DeviceCalls`; `AsyncDeviceBase`'s sync members throw instead
  of blocking; the package `RIoT2.Core.Devices.Templates`), Node `1.15.0`, Devices `1.7.0` and
  RasPi.Devices `1.6.0` (no sync shims left). Core CI generates, tests and publishes a plugin from
  the packed template, and the Node tests load it. Eight devices without async I/O stay on
  `DeviceBase` until I45 ([as built](../plans/m12-device-plugin-sdk-as-built.md#as-built-steps-56-i41),
  [guide](../guides/plugin-authoring.md)).

### I42. Wiegand peripheral (S)

- **Scope:** [M5](../plans/m05-firmware-node-runtime.md) step 4 (the firmware item in
  [features.md](../features.md)).
- **Done when:** `WiegandI2CPeripheral` publishes the card UID as a report on both boards.
- **Done 2026-11-02.** M5Core2 and M5Dial `0.6.0` register the shared `WiegandI2CPeripheral`
  (Grove PORT.A, optional IRQ on B1/B2, formats `hex`, `decimal` and `facility`). A native test runs
  it against the module's own sketch on both boards' pin maps; not yet tried on hardware
  ([plan M5 step 4](../plans/m05-firmware-node-runtime.md#steps)).

### I43. Matter completion (M)

- **Scope:** [ADR 0010](../adr/0010-finish-matter-integration.md) (A7), backlog item 8 and S10.
  Depends on I23 (the `MatterBridgeService` split).
- **Done when:** outbound bindings resolve peers through DNS-SD, a test shows bridged endpoint ids
  stay stable when node configuration changes, peer and session tables are bounded, and the S10
  fixes are in.
- **Done 2026-11-02.** RIoT2.Matter `1.1.0` (`DnsSdOperationalPeerResolver`, the default of
  `ControlBridgeService.Create`, retried every 30 s; bounded sessions, handshakes (30 s timeout),
  unsecured peers and exchanges, and mDNS instances; constant-time PASE point arithmetic; `RandomNumberGenerator` ids), Orchestrator
  `1.18.0` (`MatterEndpointStabilityTests`, which found that after a restart a new endpoint could take
  another one's id; fixed). CASE also released the session id of an abandoned handshake only on
  restart. Backlog item 8 and S10 are closed.

### I44. Mobile quick hardening (S)

- **Scope:** the parts of S11 that don't depend on the security mode: `SecureStorage` for the
  beacon key, and no FCM token in the logs. Can be done at any time.
- **Done when:** both are released in the Mobile app.
- **Done 2026-11-03.** RIoT2.Mobile `1.1.0`. `BeaconKeyStore` (behind `IBeaconKeyStore`) keeps the
  key in `SecureStorage`; the first read moves the 1.0.0 `Preferences` value there and deletes the
  plain copy; a read error is reported and retried instead of deleting the key. The payload factory
  became `BuildManufacturerDataAsync`, and the Settings page loads the key asynchronously without
  letting an early save erase it. `PushNotificationService` logs only whether the FCM token is ready.
  S11 stays open for the host allowlist and HTTPS. Not tested on a real phone.

### I45. Core 2.0: remove compatibility layers (M)

- **Scope:** M1 step 6 (remove the facade), M2 step 6 (Core without Newtonsoft, with
  `IStoredObjectService`) and the `json-naming-policy` header (M2 step 5), removing
  `IDevicePlugin.Devices`, `[Obsolete]` on `DeviceBase`, and the obsolete MQTT members from I08;
  then the source-generated `JsonSerializerContext` for the contract types (ADR 0015, M2 step 2;
  moved from I28). Completes backlog items 11 and 23.
- **Precondition:** every catalog device uses typed options and the async base class.
- **Release order:** Core 2.0 → Orchestrator, Elsa, Influx, Matter → Node together with Devices
  and RasPi.Devices. A breaking release with its own section in upgrading.md.
- **Done when:** every consumer builds and passes on Core 2.0 without the facade.
- **Done 2026-11-03.** Core `2.0.0` (ten packages), Orchestrator `1.19.0`, Elsa `1.10.0`, InfluxDB
  connector `1.11.0`, Prometheus exporter `1.1.0`, Node, Devices and RasPi.Devices `2.0.0`
  ([upgrading](../guides/upgrading.md#core-20)). The facade, Newtonsoft.Json and the obsolete members
  are gone; `RIoT2JsonOptions` keeps Newtonsoft's member order (the hashes) and reads only System.Text.Json
  attributes. `RIoT2JsonContext` resolves the contract types; the golden files didn't change. The
  precondition was part of the increment: Timer, Virtual and the six RasPi devices moved to
  `AsyncDeviceBase`, and every catalog device got typed options with its old keys. As built,
  `DeviceBase` isn't `[Obsolete]` itself: its constructors are, so only devices deriving from it
  directly get the warning, not `AsyncDeviceBase` devices. The node no longer ships Newtonsoft.Json,
  so the packer stopped excluding it (the Devices zip now holds it, for Google.Apis). Matter doesn't
  use Core and wasn't released. Review fixes: IN830 subscribed its interrupt at configuration
  instead of start; the integration test project still referenced the facade. Backlog items 11, 12
  and 23 are closed. Not tested on real hardware.

## Phase 4: features

Other ideas stay in [features.md](../features.md) until scheduled here.

### I46. System health page (M)

- **Scope:** the health page and connection banner from the feature list: node online history,
  MQTT and API state, outbox, last error per device. Depends on I22 and I36.
- **Done when:** the page shows the state of every component, and the banner appears when the UI
  loses MQTT or the API.
- **Done 2026-11-03.** Orchestrator `1.20.0` (`GET /api/v2/system/health`: checks, outbox, and every
  node, connector and workflow engine with its presence history, sync and device states with the last
  error), UI `1.10.0` (the *System* page, polled every 10 s, and the connection banner after 5 s
  without MQTT or API). As built, the history is in memory (`NodeHistory`, bounded: 20 changes per
  node, 256 nodes, 1,024 device errors) and starts at the orchestrator's start; dashboards aren't
  kept. The banner learns the API state from every request and from a ping of `/api/security/info`
  every 15 s. The delivery queue dialog stays on the Configure page and shares its panel with the
  System page.

### I47. Home Assistant connector (M)

- **Scope:** 7.3 phase 4 (Home Assistant MQTT discovery, both directions through
  `IRiot2CommandClient`).
- **Done when:** RIoT2 devices appear in Home Assistant, and commands from Home Assistant go
  through `/api/v2/commands`.
- **Done 2026-11-03.** Core `2.1.0` (`IRiot2CommandClient`, `IConnectorTemplateObserver`, richer
  `ConnectorTemplate`) and the new repository `RIoT2.Connector.HomeAssistant` `1.0.0` (image
  `riot2-homeassistant`, `deploy/compose.homeassistant.yml`). As built, every report and command
  template is a discovered entity, stale configs are deleted, report values are retained states, and
  commands from Home Assistant go only through `POST /api/v2/commands`. Home Assistant uses the RIoT2
  broker unless `RIOT2_HA_MQTT_IP` is set. The deploy check runs it with the node and checks
  `riot2/ha/status`; the nightly smoke test checks its `/health` ([design 7.3](../design/connector-sdk-as-built.md#as-built-phase-4-home-assistant-i47)).

### I48. Elsa activity pack (M)

- **Scope:** the automation activities from the feature list: debounce/window,
  threshold/hysteresis, schedule and sun-based triggers, wait-for-state, command with timeout,
  notification/webhook output, and two workflow templates.
- **Done when:** the activities are released in Elsa with tests, and the templates import into
  Elsa Studio.
- **Done 2026-11-03.** Elsa `1.11.0`: RIoT Schedule (a local time, or sunrise or sunset with an
  offset, on chosen days; `RIOT2_LATITUDE`, `RIOT2_LONGITUDE`), Compare, Threshold (hysteresis),
  Debounce, Throttle, Wait for state, Notification (through a Messaging device) and Webhook, and the
  templates `motion-light.json` and `price-based-heater.json` ([automation guide](../guides/automation.md)).
  "Command with timeout" was already RIoT Command with confirmation (I36). As built, Wait for state
  bookmarks the report's own stimulus, so reports resume it without polling; the debounce, throttle
  and threshold state is in memory; the templates are generated from code, and a test imports them
  through the service behind Studio's import.

### I55. Integrated workflows and Run LLM (M)

- **Scope:** [ADR 0016](../adr/0016-integrated-workflows-and-llm.md): replace Elsa Studio with a
  workflow designer in RIoT2.UI (ported from the maintainer's Dls project, with its Material 3 look for
  the whole UI); run Elsa in the orchestrator by default (`RIOT2_WORKFLOW_MODE=embedded`) and keep the
  container as `remote`; a *Run LLM* activity with model connections managed in the UI; Elsa 3.9.
  Depends on I48. Breaking for workflows ([upgrading](../guides/upgrading.md#integrated-workflows-and-run-llm-elsa-200-orchestrator-1210-ui-1110)).
- **Done when:** the designer creates, edits, publishes and imports workflows, and lists runs, in both
  modes; workflows saved by Studio load and run unchanged; a Run LLM step answers, reads values and
  sends allowed commands within its limits, with its usage recorded; the deploy check passes in both
  modes.
- **Release order:** Elsa `2.0.0` (the `RIoT2.Elsa.Workflows` package, then the image), Orchestrator
  `1.21.0`, UI `1.11.0`, then `deploy/`.
- **Done 2026-11-03.** Elsa `2.0.0`, Orchestrator `1.21.0`, UI `1.11.0`. As built, the `RIoT2.Elsa.Workflows` library holds the
  activities, the management service (`/riot/workflows` on the host, `/api/workflows` on the
  orchestrator) and `RIoT2.RIoTRunLlm`. The orchestrator stores embedded workflows in
  `StoredObjects/elsa.sqlite.db`, the connections as stored objects with API keys protected by keys in
  `StoredObjects/.keys`, and the usage in `StoredObjects/llm-usage.db`. The providers are OpenAI, Azure
  OpenAI, Anthropic and OpenAI-compatible servers, with the tools `ReadValues` and `SendCommands`.

### I56. Dashboard card kit (M)

- **Scope:** [ADR 0017](../adr/0017-dashboard-card-kit.md): rebuild the UI's dashboard on a card kit
  (one folder per card type, settings forms and gallery from the definitions, a scaffold); card kinds,
  card settings and page and card ids in the stored dashboard (Core 2.2.0); value schemas on report and
  command templates (device capability discovery); new cards (gauge, entities, light, motion, note,
  sensor with sparkline); a phone-first layout for RIoT2.Mobile; import and export, a preview mode and
  an unsaved-changes dialog (the [feature ideas](../features.md)); the UI's dependencies on their latest
  majors and its tests on Vitest. Depends on I55 (the Material 3 look).
- **Done when:** every legacy card type shows and edits as its new kind, and saved dashboards upgrade
  on load; a card type added with `npm run new-card` appears in the gallery and editor without other
  changes; ids survive save and reload; a dashboard exported on one system imports on another; the
  dashboard works at phone width in RIoT2.Mobile (`/dashboard/fullscreen`).
- **Release order:** Core `2.2.0`, Orchestrator `1.21.0`, UI `1.11.0` (with I55).
- **Done 2026-11-03.** Core `2.2.0`, Orchestrator `1.21.0`, UI `1.11.0`. As built, plugins declare a schema with `ValueSchema.Number`
  and the other helpers; the UI infers one from the sample model otherwise. The dashboard keeps its
  stored shape: older UIs read the cards by their legacy `type`.

### I57. MCP server and remote AI access (M)

- **Scope:** [ADR 0018](../adr/0018-mcp-server-and-remote-ai-access.md): an MCP server in the
  orchestrator (`/mcp`, `RIOT2_MCP_ENABLED`) with tool groups for values, health, commands, variables,
  workflows and configuration; the Run LLM tools and the MCP tools on one core; a remote listener on
  its own port that validates Cloudflare Access or OpenID Connect tokens (`RIOT2_MCP_AUTH`); the UI's
  *AI access* page (tool groups, allowed commands, writes per minute, the listeners' switches, the
  activity); `deploy/compose.mcp-cloudflare.yml` and the [remote AI access guide](../guides/remote-ai-access.md).
  Depends on I55.
- **Done when:** an MCP client lists only the enabled tools and sends an allowed command that the
  device executes; a command outside the allowlist or over the rate is refused; the remote port
  answers 401 without a valid token, 404 for anything but `/mcp` and its metadata, and limits a token
  to `RIOT2_MCP_REMOTE_MAX_ROLE`; ChatGPT and Claude connect through the Cloudflare overlay; the
  deploy check passes.
- **Release order:** Orchestrator `1.22.0`, UI `1.12.0`, then `deploy/` (the overlay needs
  Orchestrator `1.22.0`).

### I58. Forecasts and command plans (M)

- **Scope:** [ADR 0019](../adr/0019-forecasts-and-command-plans.md):
  - Core: forecast values on reports (`ForecastSeries`, `ForecastWindow`, `ValueSchema.Forecast`).
  - Devices: the Electricity Price `prices` series (today and tomorrow, UTC slots) and a Weather Forecast device
    (Open-Meteo, FMI open data).
  - Orchestrator: the latest series per report with window queries (`/api/v2/forecasts`), and command plans that it
    sends through the command outbox (`/api/v2/command-plans`).
  - Elsa: the RIoT Forecast and RIoT Command Plan activities.
  - AI tools: Run LLM's `read_forecast` and `PlanCommands`; MCP's `read_forecast`, `list_command_plans` and
    `plan_command`.
  - UI: the Forecast card and the *Plans* page.
  - Templates: `forecast-preheat.json` and `llm-heat-schedule.json`.
  - Contract: [forecasts.md](../contracts/forecasts.md).

  Depends on I55, I56 and I57.
- **Done when:**
  - A forecast report is kept and queried by window, in the embedded and the remote mode.
  - A plan's due step reaches the device through the command outbox; a new plan replaces the old one; after a restart
    only the latest missed step is sent.
  - Both templates import.
  - The end-to-end test `ForecastPlanEndToEndTests` passes.
- **Release order:** Core `2.3.0`, Node `2.1.0`, Devices `2.1.0`, Elsa `2.1.0` (package before the orchestrator),
  Orchestrator `1.23.0`, UI `1.13.0`.
