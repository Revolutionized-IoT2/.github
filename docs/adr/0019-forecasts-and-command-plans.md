# 0019. Forecast values on reports, and command plans the orchestrator carries out

- Status: Accepted
- Date: 2026-11-04
- Applies to: RIoT2.Core, RIoT2.Net.Devices, RIoT2.Net.Node, RIoT2.Net.Orchestrator, RIoT2.Elsa, RIoT2.UI

## Context

Workflows could react only to reports, which carry the current state. Many useful automations depend on
values ahead: "tomorrow is below 3 °C and electricity is cheaper today, so heat now", or "plan the heat pump's
temperatures from prices, the weather forecast and the inside temperature". The Electricity Price device
already downloaded day-ahead prices but reported only the current one. There was no weather forecast, and no
way to carry out a schedule of future commands. A workflow or language model could send a command only now.

## Decision

- **A forecast is a report.** Its value is a `ForecastSeries` (Core 2.3.0): `issuedAt`, `kind` (`forecast`, or
  `confirmed` for fixed values such as published prices), `unit`, `resolution`, and time-ordered, non-overlapping
  `points` of `{ start, end, value }` (UTC ISO 8601, at most 1,000). Its template declares
  `ValueSchema.Forecast(...)`, the semantic `forecast`. No topic, message or template type is added. A device must
  send the whole series again when it changes.
- **The orchestrator keeps the latest series** of every report whose value is a series, in
  `StoredObjects/forecasts.db`. It answers window queries on it (`ForecastWindow`: `all`, `today`, `tomorrow` in
  its local time zone, `next` hours, `range`) with min, max, time-weighted average, sum, the point now, the
  lowest and highest N points, and `complete`. `complete` says whether the window is covered, for example
  whether tomorrow's prices are published yet. Routes: `GET /api/v2/forecasts[/{id}]`. Workflows (`RIoT Forecast`),
  Run LLM and MCP (`read_forecast`) use the same query.
- **A command plan is the only way to schedule commands.** `POST /api/v2/command-plans` (Operator) gives one command
  1-200 `{ at, value }` steps, at least a minute apart, from 24 hours back to 7 days ahead. A command has at most one
  active plan, and a new plan replaces it. The orchestrator sends each step through the command outbox at its time
  and follows its delivery. Plans live in `StoredObjects/command-plans.db`, so they survive a restart. After a pause
  only the latest due step is sent (steps are set points); `catchUp: none` skips missed steps instead. Workflows
  (`RIoT Command Plan`), Run LLM (`PlanCommands`, within the step's allowed commands and command limit) and MCP
  (`plan_command`, within the allowed commands, as a write) use the same service. The UI's *Plans* page shows plans
  and ends them.
- **Devices:** the Electricity Price device adds a `prices` report (today and, once published, tomorrow; `confirmed`)
  and fixes its current price to UTC slots. A new Weather Forecast device reports hourly series from Open-Meteo or
  FMI open data.

## Consequences

- Workflows can decide on future data. A trigger on a forecast report, followed by `RIoT Forecast` and
  `RIoT Threshold`, fires when the forecast crosses a limit. A trigger on `prices` fires when tomorrow's prices
  arrive. The templates `forecast-preheat.json` and `llm-heat-schedule.json` show both scenarios.
- A schedule outlives the workflow run that made it, and is visible and cancellable. Workflows no longer need long
  delays or timers to act later.
- Plugins that report series need Core 2.3.0, so release the Node (2.1.0) before RIoT2.Net.Devices 2.1.0.
  `IRIoTDataService` gains methods with default implementations (Elsa 2.1.0), and the remote workflow host needs
  Orchestrator 1.23.0 for them.
- The two databases are root files in `StoredObjects/`. Like `elsa.sqlite.db`, a configuration backup doesn't
  contain them and a configuration restore keeps them. A whole-install backup contains them.
- `RIoT Threshold`'s state is in memory, so after a restart the first crossing may fire again. Because a new plan
  replaces the command's previous one, a repeat is harmless.

## Alternatives considered

- **A forecast topic and message type.** Rejected: firmware, connectors, the UI and the outbox would all need a
  second path, while a report with an entity value already reaches all of them.
- **One report per future hour.** Rejected: hundreds of templates, and no single moment when the forecast is
  complete.
- **Schedules in Elsa only (delays and loops).** Rejected: a schedule would be invisible outside the run, hard to
  replace or cancel, and a language model couldn't make one without a workflow per shape.
- **History-style storage of every series.** Not now: only the latest series is needed to decide; a connector can
  keep old ones.
