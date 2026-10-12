# Increments I49–I54: optional security mode

Applies to: all repositories, only when the optional security mode is wanted
([ADR 0004](../adr/0004-optional-security-mode.md), [design 7.5](../design/security-mode.md)).
Index, definition of done and rules: [README.md](README.md). Snapshot 2026-10-12.

Schedule these only when the system gets more users, untrusted devices or remote access. Each
one adds a feature to `RIOT2_SECURITY_FEATURES`. With `RIOT2_SECURITY_MODE=off` (the default),
nothing changes. Every increment must also pass these checks:

- With the mode `off`, all existing tests pass unchanged.
- With the mode `audit`, nothing is rejected, and every request that `on` would reject is logged.
- Switching from `on` back to `off` needs no data migration.

## Increments

### I49. Login, users and API keys (M)

- **Scope:** 7.5 phase S1 (feature `api`), backlog S1: local users, roles, cookie login,
  API keys, UI login and Admin pages, `audit` mode, `/api/security/readiness`. Depends on I34.
- **Done when:** with `api` on, anonymous requests are rejected, every role passes its
  per-endpoint authorization tests, and services authenticate with their keys.

### I50. Realtime gateway (M)

- **Scope:** 7.5 phase S2 (feature `realtime`), backlog S2. Depends on I49.
- **Done when:** with `realtime` on, the UI receives live state through the SignalR hub and the
  UI image needs no MQTT variables.

### I51. MQTT TLS and ACLs (M)

- **Scope:** 7.5 phase S3 (feature `mqtt`), backlog S3, including firmware TLS and
  `apiBaseUrl` pinning. Depends on I34.
- **Done when:** with `mqtt` on, plain connections are refused, the generated ACL file limits each
  node to its own topics, and a forged configuration command is ignored.

### I52. Endpoints and outbound policy (M)

- **Scope:** 7.5 phase S4 (features `endpoints` and `outbound`), backlog S4, S6 (endpoints),
  S7 and S8. Depends on I49.
- **Done when:** node and Elsa endpoints require the orchestrator's key, webhooks require their
  secret, Elsa uses real users, and outbound fetches follow the URL policy, with the Hue
  certificate pinned.

### I53. Signing and secrets at rest (M)

- **Scope:** 7.5 phase S5 (features `signing` and `secrets`), backlog S5, S6 (storage) and S9
  (OTA signing). Depends on I21, I30 and I35.
- **Done when:** unsigned plugins and OTA images are rejected, secret parameters and token files
  are stored as `enc:v1:` and still read with the mode off, and backups are encrypted.

### I54. Firmware and Mobile (M)

- **Scope:** 7.5 phase S6: firmware secure provisioning and storage (rest of S9), Mobile host
  allowlist and HTTPS (rest of S11). Depends on I51 and I53.
- **Done when:** the provisioning AP is protected, firmware credentials aren't stored in
  plaintext, and the Mobile app refuses hosts outside its allowlist when security is on.
