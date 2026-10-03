# Optional hardening (security mode, A1)

Applies to: all repositories, only when the optional security mode is wanted
([ADR 0002](../adr/0002-isolated-network-security-model.md)). Status: snapshot from the September 2026 platform review. Verify against the code before starting work.
IDs `S1`–`S12` are stable. (Security mode *phases* in design 7.5 are also named S0–S6; they are
a different thing.)

These are all delivered by the optional security mode designed in [7.5](../design/security-mode.md). It is off by default, can
be switched on and off, and supports a staged rollout. Until it is on, keep the network isolated.

| # | Component | Issue | Recommendation |
|---|---|---|---|
| S1 | Orchestrator | The REST API is anonymous and CORS allows any origin. | Optional authentication (local admin or OIDC, plus API keys for scripts) with roles, and a configurable CORS allowlist. |
| S2 | UI | Every browser receives the MQTT credentials. | Optional realtime gateway (SignalR/WSS) behind the same login, so browsers never hold broker credentials. |
| S3 | MQTT (all) | No TLS and no per-client ACLs. Any client can publish `riot2/node/{id}/configuration` and make a node download config from any URL. | Optional MQTT over TLS, per-identity broker ACLs, and signed or allowlisted configuration URLs. |
| S4 | Orchestrator / Core | Plugin URLs and node/workflow URLs advertised over MQTT are fetched without allowlists (SSRF). | An `HttpClientFactory` client with configurable scheme/host allowlists. |
| S5 | Node | Plugin manifests are not signed. | Signature verification in addition to the hash check in [5.1 item 5](open-issues.md). |
| S6 | Node / Devices | Webhook and download endpoints are unauthenticated. Tokens (Netatmo, Firebase service account) are stored in plaintext under `Data/`. | Per-webhook secrets/HMAC, authenticated downloads, and encryption at rest via the Data Protection API or a secret store. |
| S7 | Elsa | Uses `UseAdminUserProvider`; CORS is permissive and antiforgery is disabled. | Real identity (shared with S1), a CORS allowlist, antiforgery on. |
| S8 | Core `Utils/Web.cs` | The headers-based GET/PUT overloads skip TLS certificate validation. Only the Hue bridge (self-signed certificate) uses them; cloud integrations use the validating client. | Per-device certificate pinning instead of a blanket bypass. |
| S9 | Firmware | The provisioning AP is open and receives secrets over HTTP. Credentials are stored in plaintext NVS. OTA images are unsigned. MQTT/HTTP fall back to insecure TLS when no CA is set. | WPA2 setup AP or BLE provisioning, NVS encryption and secure boot, signed OTA manifests, fail-closed TLS. |
| S10 | Matter | The managed P-256 scalar multiplication and SPAKE2+ are not constant-time. `Random.Shared` generates session and exchange ids (`SessionManager`) and the ControlBridge commissionable instance id (`ControlBridgeService`). | Platform/hardened crypto for SPAKE2+/CASE, and `RandomNumberGenerator` for ids. |
| S11 | Mobile | The WebView accepts any URL, the beacon key lives in `Preferences`, and the default URL is HTTP. `PushNotificationService` logs the FCM token at Information level (found 2026-10-03). | Host allowlist, `SecureStorage`, HTTPS. Log the token at Debug, or not at all. |
| S12 | Docker | The UI's nginx runs as root. | Switch to `nginx-unprivileged`. |
