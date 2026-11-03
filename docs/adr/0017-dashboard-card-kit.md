# 0017. A dashboard card kit, card kinds in the stored dashboard, and value schemas

- Status: Accepted
- Date: 2026-11-03
- Applies to: RIoT2.Core, RIoT2.Net.Orchestrator, RIoT2.UI, device plugins

## Context

The dashboard had eleven card types, fixed by the `DashboardComponentType` enum in RIoT2.Core. The
UI chose a card's component with a chain of `v-if`s, and the editor had a `switch` per type for its
settings. Adding a card type meant changing Core, the orchestrator and several places in the UI.
Users edited card settings as raw JSON values, such as `onValue` or `"{temperature}"`. The editor
had no preview.

Pages and cards had no id in Core's models, so the orchestrator dropped the UI's ids when it
saved. After a reload, editing or deleting a card could change another card.

Templates carry only a sample `model`. The UI couldn't tell a temperature from a percentage, or a
range from a free number, so it couldn't build fitting inputs. The dashboard also runs embedded in
RIoT2.Mobile, so it must work on small screens.

## Decision

- **A card kit in RIoT2.UI** (`src/dashboard/`). Each card type is a folder with a `defineCard`
  definition and a Vue component. The definition gives the title, icon, category and default
  size, the settings and element slots with their defaults, a sample, and an `upgrade` from the
  legacy type it replaces. The registry finds the folders (`import.meta.glob`). The card gallery,
  the editor's forms, the preview and the tests come from the definitions.
  `npm run new-card -- <kind>` creates a card type.
- **No separate SDK package for now.** The kit is a folder of the UI with one entry point
  (`src/dashboard/sdk/index.ts`). It can move to a workspace package, as Dls's `@dls/sdk`, if card
  types are ever built outside this repository. Loading cards at run time, from plugins or URLs,
  is out of scope: it would need a security review.
- **Card kinds in the stored dashboard** (Core 2.2.0). `DashboardComponent` gets `kind`, an open
  string set, and `settings`, stored as sent. The UI still writes the closest legacy `type`, so
  older readers show something. `DashboardPage` and `DashboardComponent` get `id`. The
  orchestrator gives every page, card and element without an id a new one when it loads or saves
  the dashboard, and never changes an existing id.
- **Value schemas** (Core 2.2.0). A report or command template may declare `schema`
  (`ValueSchema`): a JSON Schema subset with a `unit` and a `semantic` meaning. The UI builds
  inputs and picks members, units, icons and cards from it, and infers a schema from the sample
  `model` when none is declared.
- **One dashboard for every screen.** The grid follows the dashboard's own width (container
  queries), and small sensor cards sit two to a row on phones. Pages are a bottom bar on phones.
  `/dashboard/fullscreen`, `?page=` and `?theme=` serve RIoT2.Mobile.

## Consequences

- A new card type is a UI change only. Its `kind` and setting keys are a stored format: they are
  never renamed, and old settings are converted in `upgrade`.
- Dashboards saved before 1.11.0 are upgraded in the UI when they load, and stored that way at the
  next save. An older UI shows an upgraded card by its `type`, with settings it may not read.
- Plugins gain a way to describe their values. Templates without a schema keep working, through
  inference.
- The UI moved to Vuetify 4, Vue Router 5, Pinia 4, Vite 8 and Vitest, and to MDI icons, with
  Material names mapped at load.

See [contracts/dashboard.md](../contracts/dashboard.md) and the
[card kit guide](https://github.com/Revolutionized-IoT2/RIoT2.UI/blob/main/src/dashboard/README.md).
