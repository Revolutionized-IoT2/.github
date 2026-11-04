# Forecasts and command plans

Applies to: RIoT2.Core (`ForecastSeries`, `ForecastWindow`), RIoT2.Net.Orchestrator (`Controllers/ForecastsController.cs`,
`Controllers/CommandPlansController.cs`, `Services/Forecasts/`, `Services/Plans/`), RIoT2.Elsa (RIoT Forecast, RIoT
Command Plan), RIoT2.UI and the device plugins that report forecasts. The decision is
[ADR 0019](../adr/0019-forecasts-and-command-plans.md). The REST conventions of [http-api.md](http-api.md#conventions)
apply.

## Forecast value (Core 2.3.0)

A forecast is an ordinary report ([mqtt-topics.md](mqtt-topics.md#report-riot2coresrccontractsmodelsreportcs)) whose
`value` is a `ForecastSeries`:

```json
{ "issuedAt": "2026-11-04T12:00:00+00:00", "kind": "confirmed", "unit": "c/kWh", "resolution": "PT1H",
  "points": [ { "start": "2026-11-04T22:00:00+00:00", "end": "2026-11-04T23:00:00+00:00", "value": 4.5 } ] }
```

- `kind` is `forecast` (predicted, may change) or `confirmed` (fixed, such as published day-ahead prices).
- `unit` and `resolution` (ISO 8601 duration) are optional. Times are ISO 8601 with an offset; devices send UTC.
- `points` must be in time order, without overlaps, `end` after `start`, at most 1,000. `value` is a number, or `null`
  when the source has none for that time.
- A device sends the whole series again when it changes, never single points.
- Its report template declares `schema` = `ValueSchema.Forecast(item)`: an `object` with the semantic `forecast`, the
  item's `unit`, and the members above, the points' `value` being `item`
  ([dashboard.md](dashboard.md#value-schema)).

Golden files: `messages/forecast-series.json` and `http/forecast-summary.json` in
[RIoT2.Core/contracts/golden](https://github.com/Revolutionized-IoT2/RIoT2.Core/blob/main/contracts/golden/README.md).

| Device (RIoT2.Net.Devices 2.1.0) | Reports |
|---|---|
| Electricity Price | `prices`: from local midnight today until tomorrow's end once ENTSO-E publishes it, `confirmed`, c/kWh with VAT; sent when it changes (the `price` report is unchanged) |
| Weather Forecast | `temperature` °C, `precipitation` mm, `windSpeed` m/s, `cloudCover` %, `solarRadiation` W/m², `humidity` %: hourly, `forecast`, from the current hour on; Open-Meteo or FMI open data |

## Forecast routes (`ForecastsController`, `api/v2/forecasts`)

Orchestrator 1.23.0, Viewer. The orchestrator keeps the latest valid series of every report whose value is one, in
`StoredObjects/forecasts.db`; an invalid series is logged and not kept. The report still updates the state and
reaches the workflows as usual.

| Method | Route | Purpose |
|---|---|---|
| GET | `/api/v2/forecasts` | `[{ id, name, node, device, kind, unit, issuedAt, receivedAt, points, from, to }]` |
| GET | `/api/v2/forecasts/{id}` | A window as a `ForecastSummary`: `?window=all\|today\|tomorrow\|next\|range` (default `all`), `hours` with `next` (1–384, default 24), `from`, `to` (ISO 8601) with `range` (at most 384 hours), `rank` (0–100). `404` without a series, `400` for a bad window. |

A `ForecastSummary` is `{ id, issuedAt, kind, unit, from, to, complete, count, min, max, average, sum, current,
points, lowest, highest }`:

- `today` and `tomorrow` are the orchestrator's local days (`TZ`); a day with a daylight saving change has 23 or 25 hours.
- `points` overlap the window. `count`, `min`, `max`, `sum` and `average` count only points with values; `average` is
  weighted by how long each point lies in the window.
- `current` is the point that applies now. `lowest` and `highest` are the `rank` lowest and highest points, lowest
  (or highest) first.
- `complete` is true when points with values cover the whole window: before tomorrow's prices are published,
  `tomorrow` is not complete.

## Command plans (`CommandPlansController`, `api/v2/command-plans`)

Orchestrator 1.23.0. Reads are Viewer, changes Operator.

| Method | Route | Purpose |
|---|---|---|
| GET | `/api/v2/command-plans` | Plans, newest first: `?commandId=`, `?active=true`, `limit` 1–500 (100) |
| GET | `/api/v2/command-plans/{id}` | A plan, or `404` |
| POST | `/api/v2/command-plans` | `{ commandId, steps: [{ at, value }], name?, source?, catchUp? }`: `201` with the plan; `400` for an invalid plan, `404` when no node owns the command |
| DELETE | `/api/v2/command-plans/{id}` | Ends the plan; the plan, or `404` |
| DELETE | `/api/v2/command-plans?commandId=` | Ends the command's active plan; the plan, or `204` when it has none |

A plan is `{ id, commandId, name, source, catchUp, status, createdAt, updatedAt, next, steps: [{ at, value, status,
correlationId, sentAt, error }] }`.

The rules for a plan:

- 1–200 steps, at least one minute apart, from 24 hours back to 7 days ahead. Names and sources are at most 200
  characters.
- A command has at most one `active` plan. A new plan makes the old one `replaced`, and the old plan's waiting steps
  `cancelled`. Ending a plan makes it `cancelled`. When no step waits any more, the plan is `completed`.
- At a step's time, its value goes through the command outbox ([http-api.md](http-api.md#commands-commandscontroller-apiv2commands))
  as the command. Its time-to-live is the time until the next step, from 30 s to 15 min.
- Step `status` values:
  - `pending`: waiting for its time.
  - `delivering`: in the outbox.
  - `executed`, `sent`, `failed`, `expired`, `unknownCommand`: as the delivery's status (`duplicate` counts as
    `executed`).
  - `skipped`: a later step was due at the same time.
  - `missed`: late by more than 2 minutes, with `catchUp` `none`.
  - `cancelled`: the plan ended first.
- When several steps are due at once (steps in the past, or after a restart), only the latest is sent. Steps are set
  points. With `catchUp` `none` (the default is `latest`), a step more than 2 minutes late is `missed` instead.
- Plans are kept in `StoredObjects/command-plans.db`. Finished ones are deleted after 30 days.

The same plans are made by:

- Elsa's RIoT Command Plan, with the source `workflow <name>`.
- Run LLM's `plan_command`, with the source `Run LLM <definition>/<activity>`.
- MCP's `plan_command`, with the source `MCP` ([mcp.md](mcp.md#tools)).
- The REST route, with the source `REST API` unless the body names one.
