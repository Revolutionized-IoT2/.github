# Increments I01–I13: phase 0 (release) and phase 1 (quality baseline)

Applies to: all repositories. Index, definition of done and rules: [README.md](README.md).
Snapshot 2026-10-12; verify the scope against the code before starting.

## Phase 0: release

### I01. Secrets and publish hygiene (S)

- **Outcome:** no usable credential is left in any public repository, and local builds can't
  leak runtime data into published output or images.
- **Scope:** [MA1](../backlog/README.md#ma1-rotate-the-leaked-credentials-and-scrub-them-from-git-history), backlog item 20.
- **Repositories:** Orchestrator, Node, and every repository whose history holds a leaked value
  (see MA1). Release: Orchestrator and Node with I02.
- **Done when:**
  - Every leaked credential is revoked and replaced, and the new values live only in `.env` files
    and GitHub secrets.
  - Rewritten histories are force-pushed, and a secret scan of every repository is clean.
  - `dotnet publish` from a developer checkout contains no `Data/` or `StoredObjects/` content,
    and the Node `.dockerignore` excludes `Data`.
- **Done 2026-10-12.** Item 20, the blank Matter controller secret, the `.gitleaks.toml`
  allowlists and [tools/secret-scan](../../tools/secret-scan/README.md). Both history rewrites
  are pushed, the credentials are rotated, and a scan of all 16 repositories is clean. The
  item 20 fix ships with the next Node and Orchestrator images (I03).

### I02. .NET 10 release train (S, deadline 10 November 2026)

- **Outcome:** everything in production runs on .NET 10 before .NET 8 and 9 lose support.
- **Scope:** [MA3](../backlog/README.md#ma3-release-the-net-10-builds-in-order) steps 2–5, MA4,
  backlog item 19 (code done 2026-10-03).
- **Release order:** Matter and ControlBridge → Influx, Orchestrator, Elsa images → Node images
  (amd64, arm64) → Devices and RasPi.Devices plugins → UI image → Mobile.
- **Depends on:** I01, so no new image or tag carries old secrets.
- **Done when:** every component is released on .NET 10, the maintainer's installation is
  upgraded by following [upgrading.md](../guides/upgrading.md), and MA3 is removed from the backlog.
- **Done 2026-10-12.** Every component is released on .NET 10 (versions in
  [MA3](../backlog/README.md#ma3-release-the-net-10-builds-in-order)), and the maintainer's
  installation is upgraded.

## Phase 1: quality baseline

### I03. CI for every repository (M)

- **Outcome:** every pull request and push builds and tests, and a release can't publish
  untested code.
- **Scope:** [M9](../plans/m09-ci-cd.md) steps 1–4 and 6 (step 1 is also [M7](../plans/m07-contract-integration-tests.md) step 1), backlog items 1 and 24.
  M9 step 5 (Renovate) is in I33. The CI also runs
  [tools/secret-scan](../../tools/secret-scan/README.md) on pushes.
- **Repositories:** `.github` (reusable workflows) first, then a caller in every repository.
- **Done when:** every repository has a `ci.yml` caller that runs on push and pull request,
  release workflows run tests before publishing, the NuGet token is passed as a build secret,
  `main` requires CI to pass, and the flaky MQTT test (item 24) is fixed.
- **Progress (2026-10-12):** done in code and released. All 16 repositories run `ci.yml` and are
  green; every release workflow validates first ([guides/ci.md](../guides/ci.md)). Items 1 and 24
  are closed. The first Linux runs found two path checks that relied on Windows rules (Devices
  download, Orchestrator store) and a C++14 link error in the firmware tests; all fixed.
  Released with the new workflows: orchestrator `1.0.1`, Elsa `1.0.2`, InfluxDB connector
  `1.0.1`, node `1.0.1`, Devices and RasPi.Devices plugins `1.0.1`, Mobile `1.0.0`, and firmware
  `0.1.0` for M5Core2, M5Dial and WiegandI2C. Remaining: required checks on `main` and retiring
  the shared token ([MA5](../backlog/README.md#ma5-require-ci-on-main-and-retire-the-shared-token)),
  and upgrading the installation to the new images and plugins.

### I04. Restart only changed devices (S)

- **Outcome:** reconnects, orchestrator restarts and unrelated saves no longer restart every device
  on a node.
- **Scope:** [design 7.2](../design/desired-state-configuration.md) phase 0, backlog item 18,
  divergence D2. No contract change.
- **Release order:** Core (patch, `DeviceServiceBase`) → Node; Orchestrator for D2.
- **Depends on:** I03.
- **Done when:**
  - Unit tests show that an identical configuration causes zero `StartDevice` calls, and that
    changing one device restarts only that device.
  - The orchestrator's last will clears the retained `riot2/orchestrator/online`, and D2 is removed
    from the divergence list.

### I05. Golden files and route contract (M)

- **Outcome:** a change that breaks a message format or calls a missing REST route fails in CI.
- **Scope:** [M2](../plans/m02-system-text-json-persistence.md) step 1, M7 steps 2–3,
  [M5](../plans/m05-firmware-node-runtime.md) step 5 (host C++ toolchain in CI for the firmware
  native tests).
- **Repositories:** Core (golden files as a test asset), Orchestrator (OpenAPI document at build
  time), UI (route test), Elsa, Influx, Ard.Shared (native parse tests). Releases: none required;
  test-only changes ship with the next release of each repository.
- **Depends on:** I03.
- **Done when:** the golden files and scrubbed `StoredObjects` samples are committed and used by
  the Core, Orchestrator, Elsa, Influx, UI and firmware tests in CI, and the UI route test fails
  for a route that the OpenAPI document doesn't contain.

### I06. In-process end-to-end harness (M)

- **Outcome:** the main flows across broker, orchestrator, node and workflow are tested
  together on every pull request, without Docker.
- **Scope:** M7 step 4. Completes backlog item 17 (with I05).
- **Repositories:** RIoT2.Tests (new `RIoT2.Tests.Integration`).
- **Depends on:** I04, I05.
- **Done when:** the harness proves that the node comes online and receives its configuration,
  that a Virtual report reaches orchestrator state and the workflow stub, that a command reaches
  the device, and that an MQTT reconnect causes zero device restarts.

### I07. Typed configuration (S)

- **Outcome:** each service reads and validates its configuration in one place.
- **Scope:** [M4](../plans/m04-typed-configuration.md) steps 1–5, backlog item 14. Environment
  variable names don't change.
- **Release order:** Core (shared options) → Orchestrator, Node, Elsa, Influx.
- **Depends on:** I03.
- **Done when:** no `GetEnvironmentVariable` call remains outside options registration, startup
  validation reports every invalid variable at once, and tests build options without changing
  process environment variables.

### I08. MQTT client robustness (M)

- **Outcome:** messages are delivered at least once, publishing while disconnected is safe, and
  one failing handler can't stop the others.
- **Scope:** [M10](../plans/m10-mqtt-client-robustness.md) steps 1–8, backlog item 3, D4.
- **Release order:** Core (minor; old members stay as `[Obsolete]` until I45) → Orchestrator,
  Node, Elsa, Influx.
- **Depends on:** I06, I07.
- **Done when:** the M10 "Done when" holds (QoS 1 everywhere in .NET, no MQTTnet types in the public
  API, a bounded pending queue, isolated handlers, configurable port), the harness passes, and D4
  is removed.

### I09. Async cleanup, part 1 (S)

- **Outcome:** the blocking calls on host paths are gone, and the Bluetooth loop can no longer
  crash the node.
- **Scope:** [M11](../plans/m11-async-cleanup.md) steps 1–2, backlog item 4 (part).
- **Release order:** Core → Node, Devices, RasPi.Devices, Elsa.
- **Depends on:** I08.
- **Done when:** the group A and C call sites listed in M11 are fixed, and a test shows that an
  exception in the Bluetooth or Ruuvi loop is logged and the loop recovers.

### I10. Plugin configuration and conformance (M)

- **Outcome:** every device shows all of its parameters in the UI, and both plugins are checked
  by one shared conformance test.
- **Scope:** [M6](../plans/m06-plugin-configuration-discovery.md) steps 1–4,
  [M12](../plans/m12-device-plugin-sdk.md) steps 1–2, backlog item 16, item 23 (part).
- **Release order:** Core (`PluginBase`, shared assembly list, `RIoT2.Core.Devices.Testing`) →
  Node (`PluginLoadContext` uses the shared list) → Devices, RasPi.Devices.
- **Depends on:** I03.
- **Done when:**
  - All 24 devices return complete templates, including the RFIDReader `interruptPin`.
  - The conformance test runs and passes in both plugin repositories.
  - Netatmo keeps no static state, and two accounts work side by side.
  - `IDevicePlugin.Devices` is marked `[Obsolete]`, and both plugins use `PluginBase`.

### I11. Durable workflow delivery (M)

- **Outcome:** a report that should trigger a workflow is delivered when Elsa is slow, restarting
  or not yet online, and is dropped only when its time-to-live has passed.
- **Scope:** [design 7.1](../design/reliable-delivery.md) phase 1 with the automation provider
  ([ADR 0006](../adr/0006-reliable-delivery.md), [ADR 0008](../adr/0008-automation-provider-interface.md)), backlog item 2 (workflow part).
- **Release order:** Elsa (deduplication) → Orchestrator.
- **Depends on:** I06, I07.
- **Done when:** the 7.1 trigger tests pass in the harness (redelivery after failure, delivery once
  a workflow node appears, expiry, duplicate `message_id`, survival across restart), and
  `/health` and `GET /api/v2/outbox/summary` report the outbox.

### I12. One-command install (S)

- **Outcome:** a new installation is `docker compose up` with one `.env` file.
- **Scope:** [design 7.4](../design/operations.md) phase 1, and S12 (`nginx-unprivileged`).
  Moving the UI to port 8080 is a breaking change, so it ships with compose.
- **Repositories:** `.github` (`deploy/`), Node (`HEALTHCHECK`), UI (unprivileged nginx).
- **Depends on:** I02.
- **Done when:** the stack starts healthy on a clean host from `.env.example`, the profile README
  quick start uses compose, and upgrading.md covers the UI port change.

### I13. Firmware OTA rollback (S)

- **Outcome:** a bad firmware image rolls back by itself instead of needing a cable.
- **Scope:** backlog item 6 and divergence C2 (template `type` parsed as a number).
- **Release order:** Ard.Shared → M5Core2.Node, M5Dial.Node.
- **Depends on:** I03, I05.
- **Done when:** an image that fails its health check before being marked valid rolls back after
  reboot (tested on one board and described in the README), both firmwares build in CI, and C2 is
  removed.
