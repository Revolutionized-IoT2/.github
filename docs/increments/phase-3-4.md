# Increments I35–I48: phase 3 (extensibility) and phase 4 (features)

Applies to: all repositories. Index, definition of done and rules: [README.md](README.md).
Snapshot 2026-10-12; verify the scope against the code before starting.

## Phase 3: extensibility

### I35. Verified plugin updates (M)

- **Scope:** [7.2](../design/desired-state-configuration.md) phase 4 on the node, backlog item 5.
  Uses the `coreVersion` rule from the [decisions to confirm](README.md#decisions-to-confirm).
- **Done when:** the node verifies the `.sha256` sidecar, rejects an incompatible `coreVersion`
  without touching `Plugins/`, installs through `Plugins.new/` and `Plugins.previous/`, rolls back
  once when loading fails (no restart loop), and reports `pendingRestart` or `failed`.

### I36. Sync and command status in the UI (M)

- **Scope:** [7.1](../design/reliable-delivery.md) phase 4 and 7.2 phase 6: sync badge, revisions,
  last error, plugin version and "re-apply" per node; command status indicator; outbox view; the
  Elsa "command with confirmation" activity (`wait:true`). Release: Elsa → UI.
- **Done when:** a changed configuration shows "applying" then "in sync", a failing command shows
  `failed` in the UI, and the Elsa activity waits for the result. Nodes without the capability
  show "legacy".

### I37. Connector SDK (M)

- **Scope:** [7.3](../design/connector-sdk.md) phase 1 ([ADR 0009](../adr/0009-connector-sdk.md)).
  Release: Core (`RIoT2.Connector.Sdk`) → Influx.
- **Done when:** the Influx connector uses the SDK, and the line protocol it writes for the golden
  messages is identical before and after.

### I38. Connector spool (M)

- **Scope:** 7.3 phase 2. Completes backlog item 2 (the Influx part).
- **Done when:** an InfluxDB outage within the spool limits loses no data, rejected batches go to
  the dead-letter file, shutdown drains to disk, and `/health` and the metrics show spool usage.

### I39. Connectors in the UI and a Prometheus exporter (M)

- **Scope:** 7.3 phase 3 (`NodeType.Connector`, UI connector list) and the Prometheus exporter
  from phase 4.
- **Done when:** connectors are listed separately in the UI, and the Prometheus exporter is
  released and scraped by the observability profile.

### I40. Nightly compose smoke test (S)

- **Scope:** [7.4](../design/operations.md) phase 5 and [M7](../plans/m07-contract-integration-tests.md) step 5.
- **Done when:** a nightly workflow starts the released compose stack, polls every `/health`
  endpoint, and reports failures.

### I41. Async-first plugins and the plugin template (M)

- **Scope:** [M12](../plans/m12-device-plugin-sdk.md) steps 5–6.
- **Done when:** `AsyncDeviceBase` no longer blocks, the host uses only async device calls, and
  `dotnet new riot2-plugin` produces a plugin that builds, packs, passes conformance and loads in
  the node.

### I42. Wiegand peripheral (S)

- **Scope:** [M5](../plans/m05-firmware-node-runtime.md) step 4 (the firmware item in
  [features.md](../features.md)).
- **Done when:** `WiegandI2CPeripheral` publishes the card UID as a report on both boards.

### I43. Matter completion (M)

- **Scope:** [ADR 0010](../adr/0010-finish-matter-integration.md) (A7), backlog item 8 and S10.
  Depends on I23 (the `MatterBridgeService` split).
- **Done when:** outbound bindings resolve peers through DNS-SD, a test shows bridged endpoint ids
  stay stable when node configuration changes, peer and session tables are bounded, and the S10
  fixes are in.

### I44. Mobile quick hardening (S)

- **Scope:** the parts of S11 that don't depend on the security mode: `SecureStorage` for the
  beacon key, and no FCM token in the logs. Can be done at any time.
- **Done when:** both are released in the Mobile app.

### I45. Core 2.0: remove compatibility layers (M)

- **Scope:** M1 step 6 (remove the facade), M2 step 6 (Core without Newtonsoft), removing
  `IDevicePlugin.Devices`, `[Obsolete]` on `DeviceBase`, and the obsolete MQTT members from I08.
  Completes backlog items 11 and 23.
- **Precondition:** every catalog device uses typed options and the async base class.
- **Release order:** Core 2.0 → Orchestrator, Elsa, Influx, Matter → Node together with Devices
  and RasPi.Devices. A breaking release with its own section in upgrading.md.
- **Done when:** every consumer builds and passes on Core 2.0 without the facade.

## Phase 4: features

Other ideas stay in [features.md](../features.md) until scheduled here.

### I46. System health page (M)

- **Scope:** the health page and connection banner from the feature list: node online history,
  MQTT and API state, outbox, last error per device. Depends on I22 and I36.
- **Done when:** the page shows the state of every component, and the banner appears when the UI
  loses MQTT or the API.

### I47. Home Assistant connector (M)

- **Scope:** 7.3 phase 4 (Home Assistant MQTT discovery, both directions through
  `IRiot2CommandClient`).
- **Done when:** RIoT2 devices appear in Home Assistant, and commands from Home Assistant go
  through `/api/v2/commands`.

### I48. Elsa activity pack (M)

- **Scope:** the automation activities from the feature list: debounce/window,
  threshold/hysteresis, schedule and sun-based triggers, wait-for-state, command with timeout,
  notification/webhook output, and two workflow templates.
- **Done when:** the activities are released in Elsa with tests, and the templates import into
  Elsa Studio.
