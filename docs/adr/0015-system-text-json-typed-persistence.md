# 0015. System.Text.Json only, with typed persistence

- Status: Accepted, implemented. The wire format runs on System.Text.Json since Core 1.11.0 ([I25](../increments/phase-2.md#i25-systemtextjson-on-the-wire-m)),
  persistence is typed since Orchestrator 1.11.0 ([I26](../increments/phase-2.md#i26-typed-persistence-m); as built, one `IStoredObjectStore`
  with `IStoredObject`-constrained methods instead of an `IObjectStore<T>` per type). Core has no
  Newtonsoft.Json and the naming-policy header is gone since Core 2.0.0 and Orchestrator 1.19.0
  ([I45](../increments/phase-3-4.md#i45-core-20-remove-compatibility-layers-m)), with the source-generated `RIoT2JsonContext`.
- Date: 2026-10-12
- Applies to: RIoT2.Core, RIoT2.Net.Orchestrator, RIoT2.Elsa, RIoT2.Connector.InfluxDB, device
  plugins, external scripts that call the orchestrator API

## Context

Core serializes with Newtonsoft while ASP.NET Core and `ValueModel` use System.Text.Json. The
orchestrator bridges the two with a `JObjectConverter` shim and offers `pascal`/`lower` naming
variants through a `json-naming-policy` header that no RIoT2 client sends. Persistence stores
`dynamic` objects and still enables `TypeNameHandling` (restricted by `RIoT2SerializationBinder`),
although current stored files carry no `$type`. [ADR 0005](0005-split-core-packages.md) already
requires the contract package to use System.Text.Json only. Plan:
[M2](../plans/m02-system-text-json-persistence.md).

## Decision

- System.Text.Json is the only serializer in Core and the services, configured once
  (`RIoT2JsonOptions`) with a source-generated context for the contract types.
- The wire format must not change. The golden files from M2 step 1 define it, and every consumer's
  tests must pass against them before and after the switch.
- Persistence is typed (`IStoredObject`, `IObjectStore<T>`). `TypeNameHandling` and `dynamic` are
  removed.
- Stored data is upgraded in place on load. A backup (increment I21) must exist before the
  release that changes the storage code. Legacy `Rule` files with `ExpandoObject` are archived,
  not converted ([ADR 0003](0003-elsa-sole-automation-engine.md)).
- The `json-naming-policy` header logs a deprecation warning for one release and is then removed.
- Core no longer depends on Newtonsoft. Plugins that need it reference it themselves.

## Consequences

- One JSON behaviour everywhere, and contract types can be trimmed and source-generated.
- External scripts that use the naming-policy header must switch to camelCase.
- Plugins that relied on Newtonsoft through Core must add their own reference. The node's plugin
  load context must not share Newtonsoft.

## Alternatives considered

- Staying on Newtonsoft: rejected, because two serializers keep producing subtle format
  differences and block the System.Text.Json-only contract package from ADR 0005.
- A separate migration tool for stored data: rejected, because loading accepts the current format
  already; only the in-memory model changes.
