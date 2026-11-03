# Design 7.5: Optional security mode (A1)

Applies to: see below. Status: **accepted 2026-10-12 ([ADR 0004](../adr/0004-optional-security-mode.md)); phase S0 done 2026-11-02 ([as built](#as-built-phase-s0-i34)), S1–S6 not implemented**. Written for the September 2026
platform review; "current behaviour" describes the code at that time. Verify before starting.
Design IDs `7.1`–`7.5` are stable. Architecture context: [target.md](../architecture/target.md).

## Principles

1. **Off by default, and off is today's behaviour exactly.** No login, anonymous REST, CORS open,
   the UI talking to MQTT directly, plain MQTT and plaintext storage.
2. **One switch per deployment.** `RIOT2_SECURITY_MODE=off|audit|on` is set once in the compose
   `.env` ([7.4](operations.md)) and read by every service through [M4](../plans/m04-typed-configuration.md) options.
   - `audit` authenticates wherever credentials are presented and logs every request that `on`
     would reject, **but never rejects**. It is the safe step between `off` and `on`.
3. **Reversible without migration.** Users, API keys, key rings and signatures are kept when the
   mode goes back to `off`; they are just not enforced. Encrypted values stay readable because the
   key ring is kept. Switching `on` again restores the previous state.
4. **Clients always send credentials when they have them; servers enforce only in `on`.** Every
   component can be given its key first, while the mode is still `off`, and the switch flipped
   afterwards.
5. **Staged rollout inside `on`.** `RIOT2_SECURITY_FEATURES` (default `all`) accepts a
   comma-separated subset: `api`, `realtime`, `mqtt`, `endpoints`, `signing`, `secrets`,
   `outbound`. With `off`, the list is ignored.
6. **Discoverable.** Anonymous `GET /api/security/info` returns
   `{ "mode": "off", "features": [], "loginRequired": false, "realtime": "mqtt" }`, so the UI and
   Mobile adapt without separate configuration.

## Seams, added while the mode is off (no behaviour change; roadmap phase 2)

| Seam | Where | While `off` |
|---|---|---|
| Authorization policies `Viewer`, `Operator`, `Admin` on every controller action: `GET` = Viewer, command execution = Operator, configuration/node/variable/dashboard/Matter writes and backup = Admin. `/health` and `/api/security/info` are anonymous. | Orchestrator, Node, Elsa RIoT endpoints | A `LocalTrust` authentication handler signs every request in as `local-admin`, so all policies pass. The audit log (feature list) still gets a user name. |
| State-changing `GET` endpoints moved to `POST`/`DELETE` ([backlog item 7](../backlog/open-issues.md)) | Orchestrator, UI | Old routes kept as aliases for one release |
| CORS policy from configuration (`RIOT2_CORS_ORIGINS`) | Orchestrator, Elsa | Any origin, as today |
| One outbound `HttpClient` from `IHttpClientFactory` with an `IOutboundUrlPolicy` hook | Orchestrator, Node, Core `Web` callers | Allow everything |
| `isSecret` flag on configuration-template parameters: `parameterDefinitions[].secret` since [I30](../increments/phase-2.md#i30-typed-device-options-m) (Core 1.16.0) | Core contracts, plugins, UI | The UI masks secret values; storage stays plaintext |
| MQTT TLS options (`RIOT2_MQTT_TLS`, `RIOT2_MQTT_CA_FILE`) in `MqttClient` | Core | Plain TCP unless set. TLS is usable even with the mode off. |
| `RealtimeTransport` interface in the UI with `mqtt` and `gateway` implementations | UI | `mqtt` |
| `X-RIoT2-Key` header sent by every service-to-service HTTP and gRPC client when `RIOT2_API_KEY` is set | Node, Elsa, Influx and SDK, Orchestrator → Node | Sent if configured, never checked |

## What each feature enables when `on`

| Feature | Behaviour | Backlog |
|---|---|---|
| `api` | **Orchestrator authentication:**<br>- Users log in with local accounts: passwords hashed with ASP.NET Core `PasswordHasher`, stored in `StoredObjects/Users`, roles Viewer, Operator or Admin.<br>- Browsers get an HttpOnly cookie with `SameSite=Strict` and send an antiforgery header on state changes.<br>- Services and scripts use API keys: `X-RIoT2-Key`, stored as SHA-256 hashes in `StoredObjects/ApiKeys`, each with a name, role and optional expiry.<br>- The first admin comes from `RIOT2_BOOTSTRAP_ADMIN_PASSWORD`; startup fails fast in `on` mode if there are no users and no bootstrap password.<br>- OIDC (`RIOT2_OIDC_AUTHORITY`, `RIOT2_OIDC_CLIENT_ID`) is an optional later addition.<br>- CORS switches to the configured origins.<br>- **Deployment change:** the UI's nginx reverse-proxies `/api` and `/realtime` to the orchestrator (`ORCHESTRATOR_UPSTREAM`), so the UI and API share an origin and cookies work in browsers and in the Mobile WebView. The proxy is harmless in `off` mode and becomes the default compose setup. | S1 |
| `realtime` | The UI uses a SignalR hub `/realtime` on the orchestrator, behind the same login, instead of MQTT. The hub relays report and state updates the orchestrator already receives, and dashboard configuration changes. The browser gets no MQTT credentials; the UI image no longer needs `VITE_MQTT_*`. | S2 |
| `mqtt` | **MQTT:**<br>- TLS required. Clients refuse plain connections.<br>- Per-identity broker accounts with ACLs. Client id = node id, so Mosquitto `pattern` rules with `%c` fit.<br>- `GET /api/security/mosquitto-acl` (Admin) generates the ACL file from the registered nodes. Templates: the orchestrator gets `readwrite riot2/#`; a node writes `riot2/node/%c/report\|online\|status\|command/result` and reads `riot2/node/%c/command\|configuration` and `riot2/orchestrator/online`; Elsa and connectors write their own `online` and read `riot2/node/+/report` (connectors also `+/command` when enabled).<br>- Nodes accept a `ConfigurationCommand.apiBaseUrl` only if it matches their `RIOT2_ORCHESTRATOR_URL`, so no one else can redirect a node's configuration download. | S3 |
| `endpoints` | **Node and Elsa endpoints:**<br>- The node REST API and download endpoint require the orchestrator's API key.<br>- Webhooks require a per-webhook secret, set as a device parameter and sent either in `X-RIoT2-Signature` (HMAC-SHA256 of the body) or as `?key=` for simple senders.<br>- Elsa replaces `UseAdminUserProvider` with its store-backed users, bootstrapped from `ELSA_BOOTSTRAP_ADMIN_PASSWORD`. Antiforgery is re-enabled, CORS is restricted, and the gRPC trigger requires the orchestrator's key in metadata. | S6, S7 |
| `signing` | **Plugin signing:**<br>- CI signs the plugin `.sha256` sidecar from [7.2](desired-state-configuration.md) with ECDSA P-256 (`System.Security.Cryptography`, key in a GitHub secret) and publishes a `.sig` file.<br>- Nodes trust the keys in `RIOT2_PLUGIN_TRUSTED_KEYS` and reject unsigned or wrongly signed packages.<br>- Firmware OTA images are verified the same way (the signed OTA manifest). | S5, S9 (OTA part) |
| `secrets` | **Secrets at rest:**<br>- Parameters flagged `isSecret` are encrypted with ASP.NET Core Data Protection before they are stored in orchestrator `StoredObjects`, using a key ring in `/app/StoredObjects/keys` and the value prefix `enc:v1:`.<br>- Node token files (Netatmo, Firebase) are encrypted the same way under `/app/Data/keys`.<br>- Reading always accepts both plaintext and `enc:v1:`, so switching off never breaks.<br>- Backups are encrypted (7.4). | S6 (storage part) |
| `outbound` | **Outbound URL policy:**<br>- The orchestrator only fetches node URLs whose host belongs to a registered online node.<br>- Plugin URLs must match `RIOT2_PLUGIN_SOURCES`, which defaults to `https://github.com/Revolutionized-IoT2/`.<br>- Hue keeps its certificate exception only for the bridge IP configured on the device, pinned to the certificate thumbprint seen on first use. | S4, S8 |

## Items that can't be switched at runtime

- **Firmware:**
  - NVS encryption and secure boot are decided when the device is flashed, via a
    `RIOT2_SECURE_BUILD` PlatformIO environment.
  - The provisioning AP password and "fail closed without CA" are settings in the provisioning
    portal, enabled automatically once the node sees `mode=on` in `/api/security/info` after its
    first connection.
- **Mobile:** the host allowlist and HTTPS requirement apply when `/api/security/info` reports
  `on` (S11). The beacon key is in `SecureStorage` in every mode since RIoT2.Mobile 1.1.0 (I44).
- **Matter** constant-time crypto and random ids (S10) didn't depend on the mode: done in
  RIoT2.Matter 1.1.0 (I43).
- **UI** nginx non-root (S12) is done: since UI 1.1.0 (I12) the image uses `nginx-unprivileged`
  on port 8080.

## Runbook

- **Turning it on:**
  1. Upgrade every component to a version with the seams.
  2. While `off`, open the Admin page (everyone is admin in `off`). Create the admin user and one
     API key per node, Elsa and connector, then put the keys in `.env`.
  3. Generate the Mosquitto ACL and TLS configuration from `deploy/mosquitto/secure/` and restart
     the broker.
  4. Set `RIOT2_SECURITY_MODE=audit` and restart. Watch the "would reject" log lines and
     `GET /api/security/readiness`, which lists nodes and services seen without a valid key, until
     both are empty.
  5. Set `RIOT2_SECURITY_MODE=on` and restart.
- **Turning it off:** set `RIOT2_SECURITY_MODE=off` and restart. Nothing else changes: keys, users
  and the TLS broker configuration can stay in place. To return to plain MQTT, switch the broker
  back to `deploy/mosquitto/default/`.

## Phases

| Phase | Content |
|---|---|
| S0 | All seams (table above), `/api/security/info`, the mode switch with `off` only, and the nginx `/api` proxy in the default compose setup. Roadmap phase 2. |
| S1 | `api` feature: users, API keys, cookie login, UI login page and Admin page, `audit` mode and `/api/security/readiness`. Clients send keys. |
| S2 | `realtime`: SignalR hub, UI gateway transport, UI image without MQTT variables in `gateway` mode. |
| S3 | `mqtt`: TLS options everywhere (.NET and firmware), ACL generator, broker templates, `apiBaseUrl` pinning. |
| S4 | `endpoints` and `outbound`: node and Elsa enforcement, webhook HMAC, URL policy. |
| S5 | `signing` and `secrets`: CI signing, node verification, Data Protection, encrypted backups. |
| S6 | Firmware secure build and provisioning, Mobile hardening. |

S1–S6 are only scheduled when security is actually needed (roadmap "Optional" row). Only S0 is
planned now.

## As built: phase S0 (I34)

Core 1.18.0, Orchestrator 1.15.0, Node 1.13.0, Elsa 1.8.0, connector 1.7.0, UI 1.7.0.

- **Settings.** `SecurityOptions` (RIoT2.Core.Mqtt) reads `RIOT2_SECURITY_MODE`,
  `RIOT2_SECURITY_FEATURES`, `RIOT2_API_KEY` and `RIOT2_CORS_ORIGINS` in every service's options.
  `SupportedModes` is `off` only: `audit` or `on` stops the start with a configuration error,
  so a deployment can't believe it is protected. The other settings are validated now.
- **Policies.** `AddRIoT2Security()` (RIoT2.Core.Hosting) registers the `RIoT2LocalTrust` scheme
  (`LocalTrustAuthenticationHandler`: `local-admin` with every role), the `Viewer`, `Operator` and
  `Admin` policies (role sets, so a higher role passes a lower policy, each naming the scheme), the
  default CORS policy and an allow-all `IOutboundUrlPolicy`. `UseRIoT2Security()` adds CORS,
  authentication and authorization, points `Web.OutboundUrlPolicy` at the policy and logs the mode.
  - Orchestrator: every controller is `Viewer`, and its writes add `Operator` (commands, report
    states) or `Admin` (nodes, variables, dashboard, Matter including the QR code, plugin checks,
    backups).
  - Node: its own routes are `Viewer`; `DefaultPolicyConvention` gives plugin actions without a
    policy `Viewer` (`GET`) or `Operator`. Devices' webhook is `Operator` this way until S4 gives it
    its secret.
  - Elsa: `POST /riot/trigger/{id}` and the gRPC service are `Operator`. Elsa's own scheme stays
    the default (`defaultScheme: false`), so Studio's login is unchanged. (Elsa 2.0.0 removed Studio
    and its login; `/riot/workflows` and the orchestrator's `/api/workflows` and `/api/llm` use the
    same policies, [ADR 0016](../adr/0016-integrated-workflows-and-llm.md).)
  - `RIoT2Security.EndpointsWithoutPolicy()` lists endpoints with neither a policy nor
    `[AllowAnonymous]`. The end-to-end suite checks the Orchestrator and the Node (with the Devices
    plugin) through it, and the Elsa tests the trigger endpoint, instead of the reflection test.
- **`GET /api/security/info`** (`MapRIoT2SecurityInfo`) returns `SecurityInfo` (RIoT2.Core.Contracts,
  in the contract schema; golden file `http/security-info.json`).
- **API key.** `ApiKeyHandler` (RIoT2.Core.Http) adds `X-RIoT2-Key` to the orchestrator's node
  client and gRPC channel, Elsa's orchestrator client and the connector's template client. The node
  adds it to its configuration download (`NodeConfigurationServiceBase.ServiceApiKey`). Devices
  never get it. Until S3 pins `apiBaseUrl`, a node sends its key to whatever URL a configuration
  command names.
- **Outbound policy.** Every `IHttpClientFactory` client gets an `OutboundUrlPolicyHandler` with
  its purpose (`node`, `orchestrator`, `workflow`, `plugin`, and `webhook` for Elsa's RIoT Webhook); `Web` checks every request (purpose
  `device` unless the caller passes one). The plugin check now uses a `HEAD` request through the
  `riot2-plugins` client.
- **MQTT TLS.** `RIOT2_MQTT_TLS` and `RIOT2_MQTT_CA_FILE` (`MqttOptions`, `MqttConfiguration`):
  MQTTnet TLS with host-name validation; with a CA file the broker's certificate must chain to it.
- **UI.** `RealtimeTransport` with `mqtt` (the MQTT service) and `gateway` (a placeholder that
  reports it isn't available until S2). The UI reads `/api/security/info` on its own origin first;
  when it answers, the API is called there, otherwise at `apiBaseUrl`. The image's entrypoint
  writes the `/api` and `/realtime` proxy from `ORCHESTRATOR_UPSTREAM`; compose sets it.
- **Not in S0:** Mobile, firmware and Matter have no seams; they adapt to `/api/security/info` in S6.

## Tests

- The [M7](../plans/m07-contract-integration-tests.md) end-to-end suite runs in CI in a matrix of `off`, `audit` and `on`, with the same
  scenarios and credentials supplied.
- **Per-endpoint authorization tests:**
  - Every controller action has a policy, enforced by a reflection test that fails on an action
    without `[Authorize(Policy=…)]` or `[AllowAnonymous]`.
  - `audit` never returns 401/403.
  - `off` accepts requests without credentials.
- A toggle round trip `off → on → off → on` keeps users, keys and encrypted values working.
- Mosquitto integration test with the generated ACL: a node can't publish another node's topics.
- Tampered or unsigned plugins are rejected in `on` and accepted, with a warning, in `off`.

## Open points (defaults chosen)

- Local accounts first, OIDC later.
- The UI moves behind the nginx `/api` proxy in every mode, to avoid cross-origin cookies.
- `audit` is a required step in the runbook, but not enforced by software.
