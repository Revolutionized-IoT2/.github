# 0005. Split Core into a contract package and runtime packages (A2)

- Status: Accepted
- Date: 2026-10-12
- Applies to: RIoT2.Core and every consumer (Orchestrator, Node, device plugins, Elsa, connectors,
  Matter), UI and firmware models

## Context

`RIoT2.Core` mixes the wire contract with the MQTT, HTTP, device and node runtimes. Every consumer
pulls in everything, plugins must share one exact Core build, and the UI and firmware copy the
models by hand. See proposal [A2](../architecture/target.md#a2-split-core-into-packages).

## Decision

- The wire contract moves to `RIoT2.Core.Contracts`: DTOs, topics, JSON Schemas and a
  source-generated System.Text.Json context, with no other dependencies.
- The runtime is split into `RIoT2.Core.Mqtt`, `RIoT2.Core.Http`, `RIoT2.Core.Devices` (the
  plugin SDK) and `RIoT2.Core.Node`. `RIoT2.Core` stays as a facade that references them, for one
  major release.
- MQTT payloads get an additive `contractVersion` field before any breaking contract change.
- JSON Schemas exported from `Contracts` are the source for the UI TypeScript models and the
  firmware C++ structs.
- The node plugin load context shares all `RIoT2.Core*` assemblies.
- Order: [M2](../plans/m02-system-text-json-persistence.md) (System.Text.Json and typed
  persistence) first, then [M1](../plans/m01-split-core-packages.md). The additive contract
  release for designs 7.1 and 7.2 ships before M1 starts.

## Consequences

- Consumers can reference only what they use, and a contract change is visible as a change to one
  package.
- All packages are released together from one tag, so versions stay aligned.
- Plugins built against the facade keep working until the facade is removed.

## Alternatives considered

Keeping one package and only adding schemas: rejected, because it doesn't stop runtime
dependencies from leaking into the contract or into plugins.
