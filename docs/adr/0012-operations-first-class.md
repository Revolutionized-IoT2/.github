# 0012. First-class operations: compose stack, logging, metrics, backup (A9)

- Status: Accepted
- Date: 2026-10-12
- Applies to: all deployable components, the `.github` repository (`deploy/`)

## Context

Each component is deployed on its own, logging differs between services, there are no metrics,
and no backup exists. See proposal [A9](../architecture/target.md#a9-make-operations-first-class)
and [design 7.4](../design/operations.md).

## Decision

- One compose stack lives in the `.github` repository under `deploy/`, configured by a single
  `.env` built from a committed `.env.example`. Optional parts (Influx, observability, Matter,
  Raspberry Pi node) are separate compose files or profiles.
- All .NET services log with Serilog through a shared `AddRIoT2Logging()` extension, with size
  and count limits on log files. JSON console output is opt-in.
- Services are instrumented with `System.Diagnostics.Metrics`. Export over OTLP happens only when
  `OTEL_EXPORTER_OTLP_ENDPOINT` is set; the observability stack is optional.
- Backup and restore exist at two levels: a configuration backup through the orchestrator API
  (no downtime), and a full-system backup script that archives every volume (short downtime).
- Backups contain secrets, and the docs must say so. They are encrypted when the security mode is
  on ([ADR 0004](0004-optional-security-mode.md)).

## Consequences

- The compose stack is the documented default installation, and a nightly compose smoke test
  becomes possible.
- New environment variables must be added to `.env.example` and
  [contracts/env-vars.md](../contracts/env-vars.md) in the same change.
- Scheduled in roadmap phases 1–3.

## Alternatives considered

Kubernetes or Helm charts: rejected as too heavy for a single-host home installation. They can be
added later on top of the same images.
