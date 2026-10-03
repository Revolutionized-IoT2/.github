# M7. Cross-repository contract and integration tests

Applies to: see the problem description. Status: snapshot from the September 2026 platform review. Verify against the code before starting work.
Index and dependencies: [plans/README.md](README.md). Backlog: [open-issues.md](../backlog/open-issues.md).

**Problem.** Each repository tests itself in isolation. The UI calling a non-existent
`GET /api/variable/{id}/value` endpoint was only found by reading code. Topic and payload
compatibility between Core, the Orchestrator, the Node, Elsa, firmware and the UI is only checked
by hand, and only Matter runs tests in CI.

## Steps

1. **Reusable CI workflow.** Add a reusable `build-test.yml` to this `.github` repository (restore,
   build, test, upload results) and call it on push/PR from every repository ([backlog item 1](../backlog/open-issues.md)).
2. **REST route contract.** Add `Microsoft.AspNetCore.OpenApi` to the Orchestrator, and
   `Microsoft.Extensions.ApiDescription.Server` to write `openapi.json` at build time. Add a UI test
   that checks every route in `RIoT2.UI/src/models/constants.ts` against that document, with the
   file copied into the UI repo or fetched from the Orchestrator release.
3. **Message contract.** Publish the golden JSON files from [M2](m02-system-text-json-persistence.md) (and later the [M1](m01-split-core-packages.md) schemas) as a test
   asset. Core, Orchestrator, Elsa, Influx and UI tests deserialize them. The firmware native tests
   parse the `Report`/`Command`/`NodeOnlineMessage`/`ConfigurationCommand` samples with the
   ArduinoJson code in `MqttJson`/`DeviceConfigurationJson`.
4. **In-process end-to-end test.** Add a `RIoT2.Tests.Integration` project that starts an in-process
   MQTTnet broker (MQTTnet 4 `MqttServer`), the Orchestrator through `WebApplicationFactory`, and
   the Node host with the `Virtual` device, plus a fake gRPC workflow endpoint. It asserts that:
   - the node comes online and receives its configuration,
   - a Virtual report reaches orchestrator state and the workflow endpoint,
   - a command sent through `POST /api/command/execute` reaches the device.

   No Docker is needed, so it runs in normal CI.
5. **Container smoke test (optional, later).** When the [A9](../architecture/target.md#a9-make-operations-first-class) `docker-compose.yml` exists, add a
   nightly workflow that starts the stack and polls every `/health` endpoint.

**Done when.** Every repository runs tests on PR, the UI route test and the shared golden files are
used by at least Core, Orchestrator, UI and firmware, and the end-to-end test runs in CI.
