# Increments I14–I34: phase 2 (platform)

Applies to: all repositories. Index, definition of done and rules: [README.md](README.md).
Snapshot 2026-10-12; verify the scope against the code before starting.

Phase 2 runs on parallel tracks. The order within each track matters; the tracks don't depend
on each other except where stated.

| Track | Increments |
|---|---|
| Protocol | I14 → I15 → I16 → I19 |
| Firmware | I17 → I18 → I19 |
| Operations | I20 → I21 → I22 |
| Structure | I23, I24, I25 → I26 → I27 → I28 |
| Plugins | I29, I30 |
| Quality | I31, I32, I33 |
| Security seams | I34 (last) |

## Protocol

### I14. Additive contract release (S)

- **Scope:** the Core parts of [7.1](../design/reliable-delivery.md) phase 2 and
  [7.2](../design/desired-state-configuration.md) phase 1 (`correlationId`, `CommandResult`,
  `NodeStatusMessage`, topics, `capabilities`, `revision`/`hash`), plus the `contractVersion` field
  ([ADR 0005](../adr/0005-split-core-packages.md)). Release: Core minor.
- **Done when:** golden files cover old and new shapes, existing consumers pass unchanged on the
  new Core, and the new fields are documented in the contracts once I15/I16 use them.
- **Done 2026-10-14.** Core `1.6.0`: the new messages, topics and fields, omitted while unset; old
  golden files unchanged.

### I15. Command results and API v2 (M)

- **Scope:** 7.1 phase 2 (orchestrator command outbox, `/api/v2/commands`, node results and
  deduplication), backlog item 7 (state-changing `GET` routes get `POST`/`DELETE` equivalents;
  the old routes stay as logged aliases for one release). Release: Node → Orchestrator.
- **Done when:** the 7.1 command tests pass (offline node `expired`, `executed`, `failed`,
  `duplicate`), and [http-api.md](../contracts/http-api.md) and
  [mqtt-topics.md](../contracts/mqtt-topics.md) describe the new behaviour. `wait` defaults to
  `false`.
- **Done 2026-10-14.** Command outbox, node results with deduplication, `/api/v2/commands`, v2
  routes for the state-changing `GET`s. Released: Core `1.7.0`, Node and Orchestrator `1.4.0`, UI
  `1.2.0`. Details: [design 7.1](../design/reliable-delivery.md#as-built-phase-2-i15).

### I16. Desired-state configuration for .NET nodes (M)

- **Scope:** 7.2 phases 2–3 and divergence D1 (retained .NET presence). Release: Node →
  Orchestrator.
- **Done when:** the 7.2 tests pass in the harness (zero restarts on reconnect and orchestrator
  restart, start from cache with the orchestrator down, a failed fetch keeps the previous
  configuration, the .NET rows of the compatibility matrix), `GET /api/nodes` returns the sync
  fields, and D1 is removed.
- **Done 2026-10-14.** Revision and hash on every configuration (`ETag`, `304`), `syncState` in
  `GET /api/nodes`; the node skips a configuration it runs, starts from its saved one, keeps it on
  a failed fetch and retains its presence (D1 fixed). Released: Core `1.8.0`, Node `1.5.0`, Orchestrator
  `1.5.0`. Details: [design 7.2](../design/desired-state-configuration.md#as-built-phases-23-i16).

## Firmware

### I17. Firmware view models (M)

- **Scope:** [M5](../plans/m05-firmware-node-runtime.md) steps 1–2. Release: Ard.Shared → both
  firmwares.
- **Done when:** shared view models have native tests, the Core2 and Dial views only render, and
  both boards behave as before.
- **Done 2026-10-14.** Twelve `riot2::views` models hold the views' state. Released: M5Core2 and
  M5Dial `0.3.0`.

### I18. Firmware NodeRuntime (M)

- **Scope:** M5 step 3, backlog item 15 ([ADR 0011](../adr/0011-firmware-noderuntime.md)).
- **Done when:** the M5 "Done when" holds for the runtime: Wi-Fi, provisioning, MQTT,
  configuration and OTA live in `NodeRuntime`, and both `main.cpp` files are thin.
- **Done 2026-10-14.** `riot2::NodeRuntime` in RIoT2.Ard.Shared runs the NVS settings,
  provisioning, Wi-Fi, MQTT and the orchestrator handshake, the deferred configuration fetch,
  templates, SNTP, OTA (trial and `system.ota`), peripherals and the BLE start-up; boards react
  through `NodeRuntimeHooks`. Board-only UI moved into board classes, so `main.cpp` is 216 lines
  on Core2 and 174 on the Dial. Backlog item 15 is done. Released: M5Core2 and M5Dial `0.4.0`.

### I19. Firmware results and desired state (M)

- **Scope:** 7.1 phase 3 and 7.2 phase 5, built once in `NodeRuntime`, plus divergence D5.
  Depends on I15, I16, I18.
- **Done when:** firmware advertises `capabilities`, publishes command results and its status,
  subscribes to commands at QoS 1, skips unchanged configurations, and passes the firmware rows of
  the 7.2 compatibility matrix.
- **Done 2026-11-01.** `NodeRuntime` advertises both capabilities, answers correlated commands,
  publishes a retained `NodeStatus`, skips the applied hash, fetches with `If-None-Match` and
  subscribes at QoS 1; D5 is fixed. Released: M5Core2 and M5Dial `0.5.0`.

## Operations

### I20. Consistent logging (S)

- **Scope:** [7.4](../design/operations.md) phase 2: shared `AddRIoT2Logging()`, Serilog in all
  four .NET services, file limits, `RIOT2_LOG_FORMAT=json`, correlation and message ids in the log
  scope. Release: Core → Orchestrator, Node, Elsa, Influx.
- **Done when:** all four services log the same way, and the new variables are in
  [env-vars.md](../contracts/env-vars.md) and `.env.example`.
- **Done 2026-11-01.** `AddRIoT2Logging()`: the same Serilog output in all four. Released: Core `1.9.0`,
  Orchestrator and Node `1.6.0`, Elsa `1.4.0`, connector `1.3.0`
  ([as built](../design/operations-as-built.md#as-built-phase-2-i20)).

### I21. Backup and restore (M)

- **Scope:** 7.4 phase 3: backup and restore API, nightly job with retention, full-system
  scripts, UI buttons. Release: Orchestrator → UI → `.github` (`deploy/`).
- **Done when:** a configuration backup restores on a fresh stack with the same nodes, devices and
  dashboards, and the full-system scripts restore every volume on a clean host. This must be done
  before I26 changes the storage code.
- **Done 2026-11-01.** Backup and restore API, *Backup* page, `backup.sh`/`restore.sh`. Released: Orchestrator `1.7.0`, UI `1.3.0`
  ([as built](../design/operations-as-built.md#as-built-phase-3-i21)).

### I22. Metrics (M)

- **Scope:** 7.4 phase 4: meters in code, OTLP export only when configured, observability compose
  profile with a provisioned dashboard. Metrics whose source doesn't exist yet are added by the
  increment that creates the source.
- **Done when:** the observability profile shows the "RIoT2 system" dashboard, and
  `riot2.node.device_restarts` stays at zero across a reconnect.
- **Done 2026-11-01.** OTLP export when configured; `compose.observability.yml` with the
  dashboard. Released: Core `1.10.0`,
  Orchestrator `1.8.0`, Node `1.7.0`, Elsa `1.5.0`, connector `1.4.0`
  ([as built](../design/operations-as-built.md#as-built-phase-4-i22)).

## Structure

### I23. Orchestrator restructure (M)

- **Scope:** [M3](../plans/m03-split-oversized-classes.md) orchestrator steps 1–3
  (`ITemplateCatalog`, `NodesController` split, `MatterBridgeService` split), backlog item 13
  (part). After I15, so the v2 routes are split too.
- **Done when:** template shaping exists in one place, no controller exceeds about 150 lines, and
  the OpenAPI document is unchanged apart from intended additions.
- **Done 2026-11-01.** Orchestrator `1.9.0`: one `ITemplateCatalog`, six controllers of at most 134
  lines, `MatterBridgeService` split (755 → 382 lines).

### I24. UI restructure and fixes (M)

- **Scope:** M3 UI steps 1–3, backlog items 10 (code splitting, ESLint), 13 (part), 21 (presence
  re-announce), 22 (labels) and divergence D3 (camelCase presence).
- **Done when:** data access lives in Pinia stores, `NodesView` is split, ESLint runs in CI, the
  main chunk is noticeably smaller, the UI re-announces on every connect, the labels are fixed and
  the screenshots are regenerated.
- **Done 2026-11-01.** UI `1.4.0`: seven Pinia stores; `NodesView` and the device configuration
  split into parts of at most 163 lines; ESLint in CI; main chunk 896 kB → 181 kB; presence re-sent
  on every connect; fixed labels, new screenshots. Four components stay in item 13.

### I25. System.Text.Json on the wire (M)

- **Decision:** [ADR 0015](../adr/0015-system-text-json-typed-persistence.md) (accepted 2026-10-12).
- **Scope:** [M2](../plans/m02-system-text-json-persistence.md) steps 2–3. Release: Core minor →
  Orchestrator, Elsa, Influx, Node.
- **Done when:** the `Json` helpers run on System.Text.Json, every consumer passes the golden
  tests, and the Newtonsoft-only entry points are `[Obsolete]`.
- **Done 2026-11-01.** Core `1.11.0`: `RIoT2JsonOptions` writes Newtonsoft's bytes. Released:
  Orchestrator `1.10.0`, Node `1.8.0`, Elsa `1.6.0`, connector `1.5.0`.

### I26. Typed persistence (M)

- **Scope:** M2 steps 4–5. M2 step 6 (dropping Newtonsoft from Core) moves to I45. Depends on I21,
  so a backup exists before the storage code changes.
- **Done when:** `StoredObjectService` has no `dynamic`, the committed `StoredObjects` samples load
  and save unchanged, legacy `Rule` files are archived, and the `json-naming-policy` header logs a
  deprecation warning.
- **Done 2026-11-01.** Orchestrator `1.11.0` on Core `1.12.0`: a typed `IStoredObjectStore` written
  with System.Text.Json (`stored-saved/` unchanged); `Rule` files move to `StoredObjects/.archive/`;
  no `JObjectConverter`; the header answers `Deprecation: true` (removed in I45).

### I27. Core package split (M)

- **Scope:** [M1](../plans/m01-split-core-packages.md) steps 1–3 and backlog item 11 (part).
  Depends on I10 (shared assembly list) and I26 (the contract package uses System.Text.Json only).
- **Done when:** all packages are published from one tag, the `RIoT2.Core` facade forwards every
  moved type, the node shares every `RIoT2.Core*` assembly, and a plugin compiled against the
  facade loads in a test.
- **Done 2026-11-01.** Core `1.13.0`: `Contracts`, `Mqtt`, `Http`, `Devices` and `Node` under
  `src/`, and the `RIoT2.Core` facade forwarding all 139 public types, released as eight packages
  from one tag. The orchestrator owns its
  interfaces (`1.12.0`); Node `1.9.0` loads a plugin built against pre-split Core 1.12.0.

### I28. Narrow references and generated models (M)

- **Scope:** M1 steps 4–5 and M3 UI step 4.
- **Done when:** Elsa and Influx no longer pull in Quartz or Hosting, plugins reference only
  `RIoT2.Core.Devices`, JSON Schemas are exported, the UI's TypeScript models are generated in
  its build, and `any` is gone from the touched UI files.
- **Done 2026-11-01.** Core `1.14.0`: every consumer on the narrowest packages. `ContractSchemas`
  exports `contracts/schemas/` on every build; RIoT2.Tests validates every golden file against it.
  UI `1.5.0` generates its models from it and has no `any` left. The source-generated context
  moved to I45. Released:
  Orchestrator `1.13.1`, Elsa `1.7.1`, connector `1.6.1` (on Core `1.14.1`), Node `1.10.0`, plugins `1.3.0`.

## Plugins

### I29. Plugin packaging (S)

- **Scope:** [M12](../plans/m12-device-plugin-sdk.md) step 3 and the CI part of 7.2 phase 4.
  Release: Core (`RIoT2.Core.Devices.Build`) → `.github` (`plugin-release.yml`) → Devices,
  RasPi.Devices.
- **Done when:** both plugin zips come from the build target with `coreVersion` and a `.sha256`
  sidecar, `plugin-release.yml` only uploads what the target produced, and a packed plugin loads
  in `PluginCompatibilityTests`. (I03 already removed the hand-written DLL list and gave
  RasPi.Devices a release workflow.)
- **Done 2026-11-02.** Core `1.15.0` adds `RIoT2.Core.Devices.Build`, whose target packs the zip,
  manifest and sidecar on `dotnet publish`; `plugin-release.yml` checks and uploads it. Devices
  and RasPi.Devices `1.3.1` use it ([as built](../plans/m12-device-plugin-sdk.md#as-built-step-3-i29)).

### I30. Typed device options (M)

- **Scope:** M12 step 4 and divergence C1, with the additive `parameterDefinitions` field. Release:
  Core minor → Orchestrator → UI → Devices, RasPi.Devices.
- **Done when:** `DeviceBase<TOptions>` binds and validates parameters, the UI renders typed
  editors and masks secrets (falling back to free text), at least the four M6 devices and
  Messaging are migrated, [configuration.md](../contracts/configuration.md) describes the field,
  and C1 is resolved.
- **Done 2026-11-02.** Core `1.16.0`: `DeviceBase<TOptions>` binds and validates `[DeviceParameter]`
  properties; templates carry `parameterDefinitions`; C1 fixed. UI `1.6.0` renders typed editors
  and masks secrets. Devices `1.4.0` migrates five devices; the rest stays in item 23
  ([as built](../plans/m12-device-plugin-sdk.md#as-built-step-4-i30)).

## Quality

### I31. Async cleanup, part 2, and threading analyzers (M)

- **Scope:** [M11](../plans/m11-async-cleanup.md) steps 3–4 and
  [M8](../plans/m08-dotnet10-migration.md) step 10. Completes backlog item 4.
- **Done when:** the threading analyzers run as errors in CI with justified suppressions only.
- **Done 2026-11-02.** Devices `1.5.0` (ten devices) and RasPi.Devices `1.4.0` (Z-Wave) on
  `AsyncDeviceBase`; Core `1.16.1`/Node `1.11.1`. VSTHRD002/100/101/110 are errors everywhere;
  item 4 is closed ([as built](../plans/m11-async-cleanup.md#as-built-i31)).

### I32. Nullable reference types (M)

- **Scope:** M8 step 9. It can also be done project by project in other increments; this
  increment finishes whatever is left.
- **Done when:** nullable is enabled in every .NET project, with warnings as errors.
- **Done 2026-11-02.** The shared `Directory.Build.props` enables it in every project. Core
  `1.17.0` is annotated (golden files and schema unchanged); Node `1.12.0`, Orchestrator `1.14.1`,
  connector `1.6.2`, Devices `1.6.0`, RasPi.Devices `1.5.0` and the tests are fixed ([as built](../plans/m08-dotnet10-migration.md#as-built-step-9-i32)).

### I33. Supply chain (S)

- **Scope:** backlog item 9 and [M9](../plans/m09-ci-cd.md) step 5.
- **Done when:** Renovate runs in every repository, base images are pinned by digest, and every
  release has an SBOM attached.
- **Done 2026-11-02**, except that Renovate starts once the maintainer installs its app (MA7).
  Every repository extends one preset (`build/renovate-preset.json`); every Dockerfile `FROM` is
  digest-pinned. Images carry SBOM and provenance attestations; plugin, NuGet, firmware and APK
  releases attach an SPDX file. Images released:
  Orchestrator `1.14.2`, Node `1.12.1`, Elsa `1.7.2`, connector `1.6.3`, UI `1.6.1`; item 9 is
  closed ([as built](../plans/m09-ci-cd.md#as-built-step-5-i33)).

## Security seams

### I34. Security seams with the mode fixed at `off` (M)

- **Scope:** [7.5](../design/security-mode.md) phase S0 ([ADR 0004](../adr/0004-optional-security-mode.md)). The `isSecret` seam comes from I30,
  and the `POST`/`DELETE` routes from I15.
- **Done when:** every seam in the 7.5 table exists and is inert, regression tests show no
  behaviour change, `GET /api/security/info` reports `off`, every endpoint has an authorization
  policy, and the compose UI reaches the API through the nginx `/api` proxy.
