# Maintainability implementation plans

Applies to: all repositories. Status: snapshot from the September 2026 platform review. Verify against the code before starting work.
Plan IDs `M1`–`M12` are stable. Each plan has its own file.

Each maintainability observation from the review has an implementation plan below and a backlog
entry ([5.1 items 11–17](../backlog/open-issues.md)). [M8](m08-dotnet10-migration.md)–[M11](m11-async-cleanup.md) are the plans for the platform and quality items that only had a
one-line recommendation: [A10](../architecture/target.md#a10-unify-engineering-practices), and [backlog items 1, 3 and 4](../backlog/open-issues.md). The plans are split into steps that
can each ship on their own and keep existing deployments working. Effort: S = up to a few days,
M = one to two weeks, L = several weeks of part-time work.

| Plan | Observation | Backlog | Effort | Depends on |
|---|---|---|---|---|
| [M1](m01-split-core-packages.md) | Core is both the wire contract and a runtime grab-bag | 11 | L | [M2](m02-system-text-json-persistence.md) (contracts package is STJ-only), [M7](m07-contract-integration-tests.md) as safety net |
| [M2](m02-system-text-json-persistence.md) | Two JSON stacks, `TypeNameHandling` and `dynamic` persistence. Step 1 done 2026-10-13 (I05) | 12 | M | M7 |
| [M3](m03-split-oversized-classes.md) | Oversized, mixed-responsibility classes | 13 | M | – |
| [M4](m04-typed-configuration.md) | Configuration read from environment variables all over the code. Steps 1–5 done 2026-10-13 (I07) | 14 (done) | S | – |
| [M5](m05-firmware-node-runtime.md) | Firmware view and wiring duplication between Core2 and Dial. Step 5 done 2026-10-13 (I03, I05) | 15 | M | – |
| [M6](m06-plugin-configuration-discovery.md) | Inconsistent plugin configuration discovery, Netatmo static state. Done 2026-10-14 (I10) | 16 (done) | S | – |
| [M7](m07-contract-integration-tests.md) | No cross-repository integration or contract test. Steps 1–4 done 2026-10-13 (I03, I05, I06); step 5 open | 17 (done) | M | M2 step 1 (golden files, done in I05) |
| [M8](m08-dotnet10-migration.md) | .NET 10 migration and shared engineering practices (A10). Steps 1–8 and 11 done and released (I02) | 19 (done) | M | [M9](m09-ci-cd.md) (CI catches regressions) |
| [M9](m09-ci-cd.md) | CI/CD for every repository. Steps 1–4 done 2026-10-12 (I03); step 5 is I33; step 6 done 2026-10-13 (MA5) | 1 (done) | M | – |
| [M10](m10-mqtt-client-robustness.md) | MQTT client robustness. Done 2026-10-13 (I08); TLS moved to I34/I51 | 3 (done) | S | – |
| [M11](m11-async-cleanup.md) | Remaining blocking and `async void` code | 4 | M | M10 (async publish), M7 |
| [M12](m12-device-plugin-sdk.md) | No device plugin SDK beyond base classes. Accepted 2026-10-12 ([ADR 0014](../adr/0014-device-plugin-sdk.md)). Steps 1–2 done 2026-10-14 (I10) | 23 | L | Steps 1–3: none ([M9](m09-ci-cd.md) for the release workflow). Step 4: M1. Step 5: M11 |

Recommended order: M9 and M7 first, as the safety net for the rest, together with M2 step 1 (the
golden message files M7 relies on). Then M10, M4 and M6 (small and independent), M11, M8, M3,
the rest of M2 and finally M1. M5 is firmware-only and can run in parallel with any of them.
M12 steps 1–2 go with M6 and step 3 with M9; steps 4–6 follow M1 and M11. The delivery order,
cut into releasable increments, is in [increments/](../increments/README.md).

## Files

- [M1](m01-split-core-packages.md) Split RIoT2.Core into contract and runtime packages
- [M2](m02-system-text-json-persistence.md) Standardize on System.Text.Json and type the persistence layer
- [M3](m03-split-oversized-classes.md) Break up oversized, mixed-responsibility classes
- [M4](m04-typed-configuration.md) Typed, validated configuration
- [M5](m05-firmware-node-runtime.md) Shared firmware view logic and node runtime
- [M6](m06-plugin-configuration-discovery.md) Consistent plugin configuration discovery and no static device state
- [M7](m07-contract-integration-tests.md) Cross-repository contract and integration tests
- [M8](m08-dotnet10-migration.md) .NET 10 migration and shared engineering practices (A10)
- [M9](m09-ci-cd.md) CI/CD for every repository ([backlog item 1](../backlog/open-issues.md))
- [M10](m10-mqtt-client-robustness.md) MQTT client robustness ([backlog item 3](../backlog/open-issues.md))
- [M11](m11-async-cleanup.md) Remaining blocking and `async void` code ([backlog item 4](../backlog/open-issues.md))
- [M12](m12-device-plugin-sdk.md) Device plugin SDK ([backlog item 23](../backlog/open-issues.md), [ADR 0014](../adr/0014-device-plugin-sdk.md))
