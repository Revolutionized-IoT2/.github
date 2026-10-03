# M3. Break up oversized, mixed-responsibility classes

Applies to: see the problem description. Status: snapshot from the September 2026 platform review. Verify against the code before starting work.
Index and dependencies: [plans/README.md](README.md). Backlog: [open-issues.md](../backlog/open-issues.md).

## Problem

- `NodesController` (342 lines, 19 actions) mixes node CRUD, online status, cron validation,
  plugin URL checks, report/command state, report/command/variable template listing and variable
  CRUD. Variable CRUD also exists partly in `VariableController`.
- The template-shaping loops that build `NodeReportTemplate`/`NodeCommandTemplate` from device
  configurations are copied in `NodesController` (report/command templates), `ReportController`
  and `CommandController`.
- `MatterBridgeService` is 624 lines.
- In the UI, `NodesView.vue` (~530 lines) and `DeviceConfigurationComponent.vue` (~500 lines)
  combine data loading, dialogs, validation and rendering. `DashboardView.vue` is ~460 lines.
- The UI still has dead scaffolding: `src/stores/counter.ts` is unused and `src/models/rules/` is
  empty (left over from the retired rule engine).

## Steps (Orchestrator)

1. Extract an `ITemplateCatalog` service with `GetReportTemplates()`, `GetCommandTemplates()`,
   `GetVariableTemplates()` and `FindReportTemplate(id)`. Replace the four copied loops with it and
   unit-test it against the golden configuration files from [M2](m02-system-text-json-persistence.md).
2. Split `NodesController` by resource, keeping every current route unchanged (use explicit
   `[Route]` attributes so URLs don't move):
   - `NodesController`: node CRUD and online status.
   - `TemplatesController`: template listing.
   - `StateController`: report and command state.
   - `VariablesController`: merged with the existing `VariableController`.
   - `PluginsController`: plugin check.
   - `CronController`: cron validation.

   [M7](m07-contract-integration-tests.md)'s route contract test proves the routes are unchanged.
3. Split `MatterBridgeService` along its existing seams (credential management, commissioning
   state, endpoint composition and report routing) into collaborators behind the
   `IMatterBridgeService` interface.

## Steps (UI)

1. Delete `stores/counter.ts` and the empty `models/rules/` folder.
2. Move data access and state into Pinia stores: `useNodesStore`, `useTemplatesStore`,
   `useVariablesStore` and `useDashboardStore`. Convert the callback-style API modules in
   `composables/api` to return promises, with loading and error state kept in the stores.
3. Split `NodesView.vue` into a node list, a node editor dialog and a device list, and split
   `DeviceConfigurationComponent.vue` into a parameters form, a report-template editor and a
   command-template editor. Target under ~250 lines per component.
4. Replace `any` (44 occurrences) in the touched files with the generated contract types from [M1](m01-split-core-packages.md)
   step 5.

**Done when.** No orchestrator controller exceeds ~150 lines, template shaping exists in one
place, no UI component exceeds ~250 lines, all REST routes are unchanged, and the UI tests pass.
