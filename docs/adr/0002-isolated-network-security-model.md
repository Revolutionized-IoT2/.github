# 0002. Isolated single-user network security model

- Status: Accepted
- Date: 2026-10-03 (records an existing decision)
- Applies to: Orchestrator, Node, UI, Elsa, connectors, firmware, MQTT broker

## Context

RIoT2 targets a home or lab network with one user. Adding login, roles and TLS everywhere would
make the system much harder to install and run, for little benefit in that setting.

## Decision

- The orchestrator REST API, the node webhook/download endpoints and the UI are anonymous. CORS is
  permissive. MQTT is plain text, and the browser connects to MQTT directly.
- Mandatory authentication must not be added. Optional hardening is planned as one switch,
  `RIOT2_SECURITY_MODE=off|audit|on`, default `off` (PLATFORM-REVIEW item A1, design 7.5).
- New code must stay easy to protect later:
  - No state changes in `GET` handlers.
  - No ad-hoc per-endpoint authentication.
  - Validate every input, because requests are not trusted to be well-formed.
- Still required now:
  - Container images must not contain credentials, IDs or IPs.
  - Containers run as non-root where possible.
  - Persisted ids must not be used as raw paths (path traversal).
  - JSON type binding stays restricted.
  - Elsa Studio keeps its own login and requires `ELSA_IDENTITY_SIGNING_KEY` in Production.

## Consequences

- Operators must keep the network isolated: no port forwarding, and a VPN for remote access.
- Device parameters stored by the orchestrator can contain third-party secrets. `StoredObjects`
  content must never be committed.
- Some legacy endpoints change state on `GET`. They are listed in
  [http-api.md](../contracts/http-api.md) and must not be copied.
- An authenticating reverse proxy and per-client Mosquitto accounts are the interim hardening
  options.

## Alternatives considered

Mandatory authentication from the start. Rejected: it adds setup cost for the main use case and
is better delivered as the optional mode above.
