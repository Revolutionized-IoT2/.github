# 0007. Desired-state configuration and verified plugin installs (A4)

- Status: Accepted
- Date: 2026-10-12
- Applies to: Orchestrator, Node, device plugins, firmware, UI, RIoT2.Core contracts, plugin CI

## Context

The node stops and restarts every device on every configuration message, including reconnects and
orchestrator restarts ([backlog item 18](../backlog/open-issues.md)). Nodes don't report what they
applied, can't start without the orchestrator, and plugins are installed without verification or
rollback. See proposal [A4](../architecture/target.md#a4-use-a-desired-state-configuration-and-plugin-model)
and [design 7.2](../design/desired-state-configuration.md).

## Decision

- Each node configuration has a `revision` and a SHA-256 `hash`, and each device configuration
  has its own `hash`. Nodes compare hashes, not revisions.
- A node applies only real changes and restarts only the devices whose hash changed.
- Nodes report their state on the retained topic `riot2/node/{id}/status`. `online` stays a
  presence signal only.
- Nodes cache the last applied configuration and start from it when the orchestrator is not
  available.
- Plugins are installed with a staged swap (`Plugins.new/` → `Plugins/` → `Plugins.previous/`),
  verified against a published `.sha256` sidecar and the `coreVersion` in the manifest, and rolled
  back automatically if loading fails. Signing is part of the optional security mode
  ([ADR 0004](0004-optional-security-mode.md)).
- All contract changes are additive; old and new nodes and orchestrators work in any combination.

## Consequences

- Phase 0 (a node-side hash and per-device diff, no contract change) fixes backlog item 18 and is
  in roadmap phase 1.
- The UI can show "in sync / applying / failed" for each node.
- Plugin CI must publish the sidecar and the manifest fields.

## Alternatives considered

Pushing the full configuration over MQTT: rejected, because firmware caps configurations at
32 KiB and the HTTP fetch works.
