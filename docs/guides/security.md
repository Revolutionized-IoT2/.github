# Security

Applies to: everyone running RIoT2. The decision behind this model is recorded in
[ADR 0002](../adr/0002-isolated-network-security-model.md).

## The model

RIoT2 is designed for an **isolated home or lab network with a single user**. In that setting:

- The orchestrator REST API, the node webhook and download endpoints, and the UI have no login.
  Every endpoint carries a role policy, but while `RIOT2_SECURITY_MODE` is `off` (the default and,
  for now, the only accepted value) every request passes as `local-admin`.
- MQTT is plain text, and the browser receives the MQTT credentials (`VITE_MQTT_*`).
- Every device that can reach these ports can read and change everything.

This is deliberate. It keeps the system simple to install and run.

## What you must still do

- **Keep the network isolated.**
  - Don't forward RIoT2 ports (1883, 9001, 80, 8080–8083, 5003) to the Internet.
  - Use a VPN for remote access.
  - The one exception is the MCP server's remote listener (port 8090), which validates a signed token
    on every request; publish it only through a tunnel with a login in front, as
    [remote-ai-access.md](remote-ai-access.md) describes. `/mcp` on port 8080 is as open as the REST API.
- **Treat stored data as secret.**
  - Device parameters can hold third-party cloud credentials (Netatmo, InfluxDB, Firebase,
    SMTP, …). They are usable from anywhere, not only from your network.
  - They live in the orchestrator's `/app/StoredObjects` (with the workflows and the encrypted API
    keys of the language model connections, and in `.keys` the key that decrypts them), the node's
    `/app/Data` (since Node 1.5.0 also `configuration.applied.json`, a copy of the node's
    configuration) and, in the remote workflow mode, Elsa's `/app/Data`.
  - Never commit these directories. Encrypt your backups: configuration backups (the
    orchestrator's `/app/Backups`) and full-system backups (`deploy/backups/`, which also holds
    `.env`) contain all of the above ([backup-and-restore.md](backup-and-restore.md)).
- **Use MQTT accounts.** Run Mosquitto with `allow_anonymous false` and a password file.
  Per-client accounts and ACLs further limit what a compromised device can do.
- **Mind what a Run LLM step may do.** Its prompt and input go to the model's provider, and with the
  `SendCommands` tool the model chooses commands. Allow only the commands it needs, keep the command
  and tool call limits low, and prefer a local OpenAI-compatible server for private data.
- **Restrict client keys.** If you build the mobile app, restrict the Firebase API key to your
  app's package and signing certificate.
- **Don't build images from a developer checkout that contains local data.**
  - Since backlog item 20 was fixed (Node and Orchestrator releases after 2026-10-12), `dotnet
    publish` and a local `docker build` leave out `Data/`, `StoredObjects/`, `MatterCredentials/`
    and `Logs/`. Older checkouts still copy them into the image.
  - Use the published images, or build from a clean clone.

## Adding protection today

When more people, untrusted devices or remote access get involved, and before the security mode
below exists:

- Put an authenticating reverse proxy in front of the UI, orchestrator and Elsa.
- Give every MQTT client its own account, with ACLs.
- Add a TLS listener to the broker. The ESP32 firmware and, since Core 1.18.0 (Orchestrator
  1.15.0, Node 1.13.0, Elsa 1.8.0, connector 1.7.0), the .NET services can use it:
  `RIOT2_MQTT_TLS=true`, plus `RIOT2_MQTT_CA_FILE` for a private CA
  ([env-vars.md](../contracts/env-vars.md#shared-variables)). The UI still connects over
  WebSocket.
- The compose UI reaches the API through its own origin (nginx proxies `/api` to the orchestrator),
  so a reverse proxy in front of the UI covers the browser's API calls too.

## Optional security mode

A single switch, `RIOT2_SECURITY_MODE=off|audit|on`, is designed in
[design 7.5](../design/security-mode.md).

- `off` is the default and behaves exactly as today. `audit` logs what would be blocked without
  blocking it.
- It adds authentication and roles, a realtime gateway instead of browser MQTT credentials, MQTT
  TLS and ACLs, signed plugins, and outbound allowlists. It can be rolled out one feature at a
  time.
- The individual issues it covers are in the
  [optional hardening backlog](../backlog/optional-hardening.md).

Only its seams exist (I34): the policies, `GET /api/security/info`, the `X-RIoT2-Key` header that
services send when `RIOT2_API_KEY` is set, CORS and outbound URL hooks, MQTT TLS and the UI's
`/api` proxy. `audit` and `on` are **not implemented yet**: a service set to either refuses to
start, rather than run unprotected. Increments I49–I54 add them when needed.
