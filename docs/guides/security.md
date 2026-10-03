# Security

Applies to: everyone running RIoT2. The decision behind this model is recorded in
[ADR 0002](../adr/0002-isolated-network-security-model.md).

## The model

RIoT2 is designed for an **isolated home or lab network with a single user**. In that setting:

- The orchestrator REST API, the node webhook and download endpoints, and the UI have no login.
- MQTT is plain text, and the browser receives the MQTT credentials (`VITE_MQTT_*`).
- Every device that can reach these ports can read and change everything.

This is deliberate. It keeps the system simple to install and run.

## What you must still do

- **Keep the network isolated.**
  - Don't forward RIoT2 ports (1883, 9001, 80, 8080–8083, 5003) to the Internet.
  - Use a VPN for remote access.
- **Treat stored data as secret.**
  - Device parameters can hold third-party cloud credentials (Netatmo, InfluxDB, Firebase,
    SMTP, …). They are usable from anywhere, not only from your network.
  - They live in the orchestrator's `/app/StoredObjects`, the node's `/app/Data` and Elsa's
    `/app/Data`.
  - Never commit these directories. Encrypt your backups.
- **Use MQTT accounts.** Run Mosquitto with `allow_anonymous false` and a password file.
  Per-client accounts and ACLs further limit what a compromised device can do.
- **Set a strong `ELSA_IDENTITY_SIGNING_KEY`** (for example `openssl rand -base64 48`). Don't
  expose Elsa Studio beyond the trusted network: its built-in admin account is not meant for
  hostile networks.
- **Restrict client keys.** If you build the mobile app, restrict the Firebase API key to your
  app's package and signing certificate.
- **Don't build images from a developer checkout that contains local data.**
  - A local `docker build` or `dotnet publish` can copy `Data/` (node) or `StoredObjects/`
    (orchestrator) into the image (backlog item 20).
  - Use the published images, or build from a clean clone.

## Adding protection today

When more people, untrusted devices or remote access get involved, and before the security mode
below exists:

- Put an authenticating reverse proxy in front of the UI, orchestrator and Elsa.
- Give every MQTT client its own account, with ACLs.
- Add a TLS listener to the broker. The ESP32 firmware can use MQTT over TLS, but the .NET
  services can't yet.

## Planned: optional security mode

A single switch, `RIOT2_SECURITY_MODE=off|audit|on`, is designed in
[design 7.5](../design/security-mode.md).

- `off` is the default and behaves exactly as today. `audit` logs what would be blocked without
  blocking it.
- It adds authentication and roles, a realtime gateway instead of browser MQTT credentials, MQTT
  TLS and ACLs, signed plugins, and outbound allowlists. It can be rolled out one feature at a
  time.
- The individual issues it covers are in the
  [optional hardening backlog](../backlog/optional-hardening.md).

This mode is **not implemented yet**.
