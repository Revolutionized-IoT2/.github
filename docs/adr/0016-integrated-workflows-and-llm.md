# 0016. An integrated workflow designer, embedded workflows by default, and a Run LLM step

- Status: Accepted
- Date: 2026-11-03
- Applies to: RIoT2.Elsa, RIoT2.Net.Orchestrator, RIoT2.UI, deploy/

## Context

Automations were built in a customized Elsa Studio (a Blazor WebAssembly app in the `riot2-elsa`
container). It had its own look, its own login (`ELSA_IDENTITY_SIGNING_KEY`, the built-in `admin`
account) and its own port. It also needed the separate container for every installation, even a
small one. Its RIoT selector had to be written in Blazor, apart from the rest of the UI.

The maintainer's Dls project shows another way: a Vue Flow designer inside the app's own UI that
talks to the app's API, Elsa hosted in the app's process, and a *Run LLM* activity whose model
connections and secrets stay on the server.

[ADR 0003](0003-elsa-sole-automation-engine.md) (Elsa is the only engine) and
[ADR 0008](0008-automation-provider-interface.md) (automation behind `IAutomationProvider`) still apply.

## Decision

- **No Elsa Studio.** RIoT2.UI's *Workflows* pages (`/workflows`, `/workflows/:id`) are the only
  designer. They call the orchestrator's `/api/workflows`, never Elsa directly. The designer edits
  Elsa's own definition model, so properties it doesn't know survive a save. The RIoT selector
  writes the same literal Studio wrote, so existing workflows load unchanged. Elsa's Identity module
  and Workflows API are removed from the workflow host, and with them `ELSA_IDENTITY_SIGNING_KEY`.
- **One engine library, two hosts.** The RIoT activities, the management service and the Run LLM
  activity are in the `RIoT2.Elsa.Workflows` package. The orchestrator and the `riot2-elsa`
  container both host it.
- **Where workflows run is a setting.** `RIOT2_WORKFLOW_MODE=embedded` (the default) runs Elsa in the
  orchestrator: definitions in `StoredObjects/elsa.sqlite.db`, triggers handed from the outbox to
  the engine in process, and values read and commands sent without HTTP. `remote` keeps the
  `riot2-elsa` container. Triggers are delivered over gRPC as before, and the orchestrator forwards
  `/api/workflows` to the host's `/riot/workflows`. The UI and the activities are the same in both
  modes. Only one mode runs at a time.
- **Run LLM.** `RIoT2.RIoTRunLlm` runs one prompt through a named connection (OpenAI, Azure OpenAI,
  Anthropic or an OpenAI-compatible server). Connections are managed on the UI's *AI models* page
  through `/api/llm`. The orchestrator keeps their API keys encrypted with ASP.NET Data Protection
  (keys in `StoredObjects/.keys`) and never returns them. Every call goes through the orchestrator's
  `ILlmRunner`; the remote host calls `POST /api/llm/run`. The step's tools can read template values
  and send commands, limited per step (allowed commands, at most N commands and N tool calls, a
  timeout). Every run's tokens are recorded in `StoredObjects/llm-usage.db`.

## Consequences

- Small installations need one container fewer, and the workflow designer looks and behaves like the
  rest of the UI. The UI moved to the Material 3 look of Dls (Vuetify blueprint `md3`, light and dark).
- Breaking for deployments that keep their workflows in the `riot2-elsa` container. Either copy
  `elsa.sqlite.db` into the orchestrator's `StoredObjects` or set `RIOT2_WORKFLOW_MODE=remote`
  ([upgrading.md](../guides/upgrading.md#integrated-workflows-and-run-llm-elsa-200-orchestrator-1210-ui-1110)).
  Never run both: a schedule would fire twice.
- Elsa 2.0.0 drops Studio, the Elsa Workflows API and Identity. Elsa moves to 3.9.0.
- Configuration backups don't contain the workflow database or the Data Protection keys. Backups of
  the whole install (`deploy/backup.sh`) contain both. A restored configuration's LLM connections
  need their API keys entered again unless the keys come back too.
- The `/workflows` path on the orchestrator's port is Elsa's HTTP endpoint activity base path in the
  embedded mode. The remote host keeps `/api/workflows`.

## Alternatives considered

- **Keep Studio and restyle it.** Rejected: it would keep a second UI stack, a second login and the
  container.
- **A separate workflow web app.** Rejected: it would bring a second origin, a second navigation and
  a second auth story.
- **Embedded only.** Rejected: the container lets heavy or experimental workflows run apart from the
  orchestrator, and existing installations can keep it.
- **LLM calls straight from the workflow host with its own keys.** Rejected: secrets would be in two
  places, and usage couldn't be tracked in one store.
