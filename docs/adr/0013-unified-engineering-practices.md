# 0013. Unified engineering practices across .NET repositories (A10)

- Status: Accepted
- Date: 2026-10-12
- Applies to: every .NET repository; CI in every repository

## Context

The repositories used different .NET versions and package-management styles, ad-hoc configuration
reading, no shared CI, and no test that covers more than one component. See proposal
[A10](../architecture/target.md#a10-unify-engineering-practices).

## Decision

- Every .NET repository targets one .NET version, currently .NET 10 LTS, and uses central
  package management (`Directory.Packages.props`) and the shared build templates in
  [build/](../../build/README.md).
- Analyzers run with warnings as errors in CI. Nullable reference types and the threading
  analyzers are enabled progressively ([M8](../plans/m08-dotnet10-migration.md) steps 9–10).
- Services read configuration through typed `IOptions<T>` with validation at startup
  ([M4](../plans/m04-typed-configuration.md)).
- Every repository uses the reusable GitHub workflows from the `.github` repository
  ([M9](../plans/m09-ci-cd.md)).
- A cross-repository platform integration test runs broker, orchestrator, node (Virtual device)
  and a workflow stub in-process; container smoke tests are added later
  ([M7](../plans/m07-contract-integration-tests.md)).

## Consequences

- Done 2026-10-03: .NET 10, central package management, shared build templates, analyzers with
  warnings as errors, and SourceLink (M8). Done 2026-10-13: typed configuration (M4, I07) and
  the contract and end-to-end tests (M7 steps 1–4, I03–I06). Nullable, threading analyzers, M7
  step 5 and the rest of M9 are open.
- A new repository starts from the build templates and the reusable workflows.
- Moving to the next .NET LTS is one coordinated change across all repositories.

## Alternatives considered

Letting each repository choose its own versions and tooling: rejected, because plugins must load
into the node, and Core must be consumable by everything.
