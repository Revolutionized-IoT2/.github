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
  ([as built](../design/connector-sdk.md#as-built-phase-1-i37)).

### I38. Connector spool (M)

- **Scope:** 7.3 phase 2. Completes backlog item 2 (the Influx part).
- **Done when:** an InfluxDB outage within the spool limits loses no data, rejected batches go to
  the dead-letter file, shutdown drains to disk, and `/health` and the metrics show spool usage.
- **Done 2026-11-02.** Core `1.21.0`, connector `1.9.0` (new volume `/app/Data`). Messages move to
  disk at the first failure and are written in order once InfluxDB is back; a restart resumes from
  the checkpoint; backlog item 2 is closed. The memory queue's high-water mark (80 %) sends new
  messages to the spool ([as built](../design/connector-sdk.md#as-built-phase-2-i38)).

### I39. Connectors in the UI and a Prometheus exporter (M)

- **Scope:** 7.3 phase 3 (`NodeType.Connector`, UI connector list) and the Prometheus exporter
  from phase 4.
- **Done when:** connectors are listed separately in the UI, and the Prometheus exporter is
  released and scraped by the observability profile.
- **Done 2026-11-02.** Core `1.22.0` (`NodeType.Connector`, presence with name, URL and version),
  Orchestrator `1.17.0` (`GET /api/v2/connectors` with each connector's health), UI `1.9.0` (connector
  list), InfluxDB connector `1.10.0`, and the new repository `RIoT2.Connector.Prometheus` `1.0.0`
  (`riot2_value` at `/metrics`, job `riot2-values`, dashboard "RIoT2 values")
  ([as built](../design/connector-sdk.md#as-built-phases-3-and-4-i39)).

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

- **Scope:** M1 step 6 (remove the facade), M2 step 6 (Core without Newtonsoft, with
  `IStoredObjectService`) and the `json-naming-policy` header (M2 step 5), removing
  `IDevicePlugin.Devices`, `[Obsolete]` on `DeviceBase`, and the obsolete MQTT members from I08;
  then the source-generated `JsonSerializerContext` for the contract types (ADR 0015, M2 step 2;
  moved from I28). Completes backlog items 11 and 23.
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
