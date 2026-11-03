# Open issues (applies now)

Applies to: all repositories. Status: snapshot from the September 2026 platform review. Verify against the code before starting work.
IDs `1`–`26` are stable; refer to them as "backlog item N". Items 1–19 come from the September 2026 review; later items carry the date they were found. Done items are removed and their IDs are never reused: 1 (CI, I03), 3 (MQTT client robustness, I08), 6 (OTA rollback, I13), 15 (firmware views and runtime duplicated between the boards, I17 and I18), 14 (configuration read from environment variables in four styles, I07), 16 (hidden device parameters and static Netatmo state, I10), 17 (no end-to-end test, I05 and I06), 18 (all devices restarted on every configuration message, I04), 19 (.NET 10, I02), 20 (publish leak, I01), 24 (flaky MQTT test, I03), 10 (UI bundle size and ESLint, I24), 21 (UI presence sent only once, I24), 22 (stale UI labels, I24), 4 (blocking device drivers, I09 and I31), 9 (unpinned base images, no SBOM, I33), 5 (unverified plugin installs, I35) 2 (Influx writes lost in an outage, I37 and I38) and 8 (unbounded Matter peer and session tables, I43), 11 (the Core facade), 12 (Newtonsoft in Core and the naming-policy header) and 23 (the rest of the device plugin SDK), all three in I45. Optional hardening items `S1`–`S12`
are in [optional-hardening.md](optional-hardening.md).

The September 2026 review left these unfixed, because each one needs a design decision or a
coordinated contract change.

**Deployment context.** Today RIoT2 runs on an isolated network with a single user. Every device
on that network is trusted, and nothing is exposed to the Internet except the platform's own
outbound calls to cloud services (Netatmo, electricity price and so on). The severities below are
rated for that context. Issues that only matter once the system is reachable by untrusted devices
or by more than one user are listed separately in [5.2](optional-hardening.md) as optional hardening, delivered through
architecture item [A1](../architecture/target.md#a1-optional-security-mode). They don't block production use in the current setup.

## Items

| # | Severity | Component | Issue | Recommendation |
|---|---|---|---|---|
| 7 | Low | Orchestrator | Since I15 (Orchestrator 1.4.0) the six state-changing `GET` routes have `POST`/`DELETE` routes under `/api/v2`, and UI 1.2.0 uses them. The old `GET` routes still work as deprecated, logged aliases. | Remove the aliases in a later orchestrator release, once no installation runs a UI older than 1.2.0. This also avoids CSRF issues if A1 is enabled later. |
| 13 | Low | UI | Four UI components are still over about 250 lines: `DashboardView.vue` (470), `EditModeComponent.vue` (331), `DatamodelComponent.vue` (329) and `VariablesView.vue` (270). The rest is done: the orchestrator split ([I23](../increments/phase-2.md#i23-orchestrator-restructure-m)), and the Pinia stores, the `NodesView` and device configuration splits and the scaffolding removal ([I24](../increments/phase-2.md#i24-ui-restructure-and-fixes-m)). | Move their dialogs and editors into child components, as the Configure page does. Plan: [M3](../plans/m03-split-oversized-classes.md). |
| 25 | Low | Tests | Found 2026-10-14. `LifecycleReliabilityTests.RetainedMessageIsReceivedOnStartAndPresenceIsSentAfterReconnect` (RIoT2.Tests) fails about one run in five when the whole suite runs: MQTTnet's managed client throws `MqttProtocolViolationException` ("Received packet 'PubAck' at an unexpected time") while it publishes queued messages after the test restarts the broker. Unrelated to the code under test so far; the same may happen in production after a broker restart. | Reproduce with the MQTTnet managed client alone; check whether `MqttClient` should catch the exception and reconnect, or whether a newer MQTTnet fixes it. Seen again in RIoT2.Tests CI on 2026-11-01, three times (I25, I28; reruns passed). On 2026-11-02 (I35) the end-to-end `MqttReconnectRestartsNoDevice` also timed out once waiting for the node's answer after a reconnect; the rerun passed. |
| 26 | Low | Deploy | Found 2026-11-01. The hub's deploy-check job "smoke (stack and influx)" once got `404` from `GET http://<host>/` (the UI) half a second after the UI container reported healthy; the rerun passed, and the two other jobs ran the same step fine. The UI's `entrypoint.sh` starts nginx only after rendering the bundle, so the cause is unknown. | If it recurs, log the UI container and the response body, and check what answers on port 80 on the runner before adding a retry. |
