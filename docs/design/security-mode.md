# Design 7.5: Optional security mode (A1)

Applies to: see below. Status: **proposed, not implemented**. Written for the September 2026
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
| `isSecret` flag on configuration-template parameters ([M6](../plans/m06-plugin-configuration-discovery.md) adds the templates) | Core contracts, plugins, UI | The UI masks secret values; storage stays plaintext |
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
- **Mobile:** the host allowlist, HTTPS requirement and `SecureStorage` apply when
  `/api/security/info` reports `on`. Moving the beacon key to `SecureStorage` is harmless in `off`
  mode as well and can be done at any time (S11).
- **Matter** constant-time crypto and random ids (S10) are code-quality fixes that don't depend on
  the mode. Do them whenever Matter is worked on.
- **UI** nginx non-root (S12): the image can switch to `nginx-unprivileged` whenever the port
  mapping changes. It doesn't depend on the mode either.

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
