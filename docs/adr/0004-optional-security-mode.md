# 0004. Optional, switchable security mode (A1)

- Status: Accepted
- Date: 2026-10-12
- Applies to: Orchestrator, Node, Elsa, connectors, UI, Mobile, firmware, MQTT broker, deployment

## Context

[ADR 0002](0002-isolated-network-security-model.md) keeps RIoT2 anonymous because it runs on an
isolated single-user network. That may change: more users, untrusted devices or remote access.
Proposal [A1](../architecture/target.md#a1-optional-security-mode) and
[design 7.5](../design/security-mode.md) describe how security can be added without changing the
default experience.

## Decision

- Security is one deployment-wide switch, `RIOT2_SECURITY_MODE=off|audit|on`, default `off`.
  `RIOT2_SECURITY_FEATURES` (default `all`) selects a subset in `on`: `api`, `realtime`, `mqtt`,
  `endpoints`, `signing`, `secrets`, `outbound`.
- `off` must behave exactly like today. `audit` must log what `on` would reject and must never
  reject.
- Switching between modes must not need a data migration. Users, keys and key rings are kept
  when the mode is `off`, and readers accept both plaintext and `enc:v1:` values.
- The seams (authorization policies with a `LocalTrust` handler, CORS from configuration, the
  outbound URL policy hook, `isSecret` template flags, MQTT TLS options, the UI realtime transport,
  the `X-RIoT2-Key` header) are added early and must be inert while the mode is `off`.
- Clients send credentials whenever they have them. Servers enforce only in `on`.
- Security is never implemented per endpoint or per repository on its own. It goes through the
  shared seams and the mode switch.

## Consequences

- ADR 0002 stays in force for the default `off` mode. This ADR defines how it can be relaxed.
- Phase S0 (seams, `/api/security/info`, the UI nginx `/api` proxy) is scheduled in roadmap
  phase 2. Phases S1–S6 and backlog items S1–S12 are done only when needed.
- Every new endpoint gets an authorization policy (Viewer, Operator or Admin) from the start,
  even though `LocalTrust` passes it while `off`.
- Elsa Studio keeps its own login in all modes.

## Alternatives considered

- Mandatory authentication: rejected in ADR 0002.
- Per-feature switches in each service: rejected, because a deployment could end up half secured
  in ways nobody can see. One switch plus a feature list keeps the state visible through
  `/api/security/info`.
