# Automation with Elsa: the RIoT activities and templates

Applies to: RIoT2.Elsa `2.0.0`, Orchestrator `1.21.0` and UI `1.11.0` and later. How to build
automations on the UI's **Workflows** page with the RIoT activities, and how to start from the
workflow templates. The activities' code is in
[RIoT2.Elsa](https://github.com/Revolutionized-IoT2/RIoT2.Elsa/blob/master/README.md); why Elsa is the
only automation engine is in [ADR 0003](../adr/0003-elsa-sole-automation-engine.md), and why the
designer is in the UI and Elsa runs in the orchestrator in [ADR 0016](../adr/0016-integrated-workflows-and-llm.md).
Before Elsa 2.0.0 the same activities were in Elsa Studio.

## How a workflow is started

The orchestrator hands every report to Elsa through its outbox: in process when Elsa is embedded
(`RIOT2_WORKFLOW_MODE=embedded`, the default), or over gRPC to the Elsa container (`remote`), where
the outbox keeps them while the container is offline, for `RIOT2_OUTBOX_WORKFLOW_TTL` (5 minutes). Each report is a stimulus named after the
report id: it starts the published workflows whose **RIoT Trigger** selects that report, and resumes
the ones waiting for it in **RIoT Wait for state**. **RIoT Schedule** starts workflows at a time of
day, or at sunrise or sunset.

The report that started a workflow is its input `EventData` (`{ id, value, timeStamp, … }`). RIoT
Compare and RIoT Threshold use it when their `Value` is left empty, so most automations need no
JavaScript.

## Activities

All are in the **RIoT** group of the designer's palette. Drag one onto the canvas, connect its
outcomes to the next activities, and set its inputs in the inspector on the right. An input can be a
literal or an expression (JavaScript, Liquid); the RIoT selectors list your reports, commands and
variables. The designer warns about a missing trigger, an unconnected activity or an empty selector
before you publish.

| Activity | Use it to | Outcomes |
|---|---|---|
| RIoT Trigger | Start a workflow on a report | `Done` |
| RIoT Schedule | Start a workflow at `07:30`, `sunrise`, `sunset-30`, …, on chosen days | `Done` |
| RIoT Data | Read a report, variable or command value | `Done` |
| RIoT Compare | Filter: the triggering report (or `Value`) equals, is greater than, … a constant | `True`, `False` |
| RIoT Threshold | React when a value crosses a limit, with hysteresis | `Above`, `Below`, `Unchanged` |
| RIoT Debounce | Act once a burst of events has ended ("5 minutes after the last motion") | `Done`, `Superseded` |
| RIoT Throttle | Act at most once per window ("notify at most once an hour") | `Pass`, `Suppressed` |
| RIoT Wait for state | Wait until a report has a value, with a timeout | `Done`, `Timed out` |
| RIoT Output | Send a command (or set a variable); the value is a JavaScript expression | (ends the path) |
| RIoT Command with confirmation | Send a command and wait up to 50 s for the device's result | `Done`, `Failed` |
| RIoT Notification | Push to the Mobile app or send a mail through a Messaging device | `Done` |
| RIoT Webhook | Call an HTTP endpoint | `Done`, `Failed` |
| Run LLM | Have a language model answer, decide or act | `Done`, `Failed` |

### Compare and Wait for state

`Operator` is one of `equals`, `not equals`, `greater than`, `less than`, `at least`, `at most`;
`Expected` is a text. A number compares as a number (`21.5`), a boolean with `true`/`false`,
`on`/`off` or `1`/`0`, and a text ignoring case. The order comparisons need numbers on both sides.

RIoT Wait for state first reads the report's latest value from the orchestrator and continues at
once if it matches. Otherwise the workflow is suspended until a matching report arrives, or until
`TimeoutSeconds` (300; at most 7 days) passes. Its output `Value` is the value that matched.

### Threshold, Debounce and Throttle

- **Threshold.** The state becomes high above `Upper` and low below `Lower`, and stays as it was in
  between. Set both to the same number for a plain threshold. `Above` and `Below` come only when the
  state changes; repeated values give `Unchanged`. The output `State` is `high`, `low` or `unknown`.
- **Debounce.** Every run waits `WindowSeconds`; only the last run of a burst continues on `Done`,
  the earlier ones on `Superseded`.
- **Throttle.** The first run continues on `Pass`; the others within `WindowSeconds` of it on
  `Suppressed`.

These three keep their state between workflow runs, per activity in a workflow definition. Give
several activities the same `Key` to share it. The state is in Elsa's memory: after a restart a
threshold starts `unknown`, a throttle lets the next run pass, and a waiting debounce continues on
`Done`.

### Schedule

`At` is a 24-hour local time (`07:30`), `sunrise` or `sunset`, with an optional offset in minutes
(`sunset-30`, `sunrise+15`, at most 720). `Days` is empty (every day), `weekdays`, `weekends` or
day names (`mon,wed,fri`). The output `FiredAt` is the time it was due.

- Times are in Elsa's time zone, `TZ` (compose sets `Europe/Helsinki` unless `.env` changes it). A
  time skipped by a daylight saving change fires at the end of the gap; a repeated time fires once.
- Sunrise and sunset need `RIOT2_LATITUDE` and `RIOT2_LONGITUDE` in `.env` (decimal degrees, north
  and east positive, for example `60.17` and `24.94`); without them, sun-based schedules don't fire
  and Elsa logs a warning. On days the sun doesn't rise or set (polar night, midnight sun) nothing
  fires.
- A time missed while Elsa was stopped, or more than a minute late (a clock jump), is not fired
  afterwards; when the clock goes back, nothing fires twice.
- Inside a workflow (not as its start), RIoT Schedule waits for the next such time.

### Notification and Webhook

**RIoT Notification** sends a command to a [Messaging device](https://github.com/Revolutionized-IoT2/RIoT2.Net.Devices/blob/main/README.md):
choose its *Send firebase message* command to push to the Mobile app (`Topic` `alerts` or
`notifications`, optional `ImageUrl`), or *Send mail message* to mail `To`. `Title` is the
mail's subject. The command goes through the orchestrator's outbox like any other.

**RIoT Webhook** sends `Body` (`ContentType`, default `application/json`, always with
`charset=utf-8`) with `Method` (default `POST`) to `Url`, and waits `TimeoutSeconds` (10, at most 60). A 2xx answer continues on `Done`;
any other status, a timeout or a network error on `Failed`, with `StatusCode`, `ResponseBody` (at
most 64 KiB) and `Error` as outputs. With the security mode's outbound policy the purpose is
`webhook` ([design 7.5](../design/security-mode.md)). Elsa's own *HTTP Request* activity remains for
anything more elaborate.

### Run LLM

**Run LLM** sends `Instructions` and `InputData` (any JSON, for example the trigger's `EventData`)
to a model and continues on `Done` with its answer, or on `Failed` with `ErrorCode` and `Error`.

1. On the UI's **AI models** page, add a connection: OpenAI, Azure OpenAI (the endpoint and the
   deployment as the model), Anthropic, or an OpenAI-compatible server such as Ollama, LM Studio or
   vLLM. The orchestrator stores the API key encrypted and never shows it again. **Test** checks the
   connection.
2. In the step, choose the `Connection` by name and write the `Instructions`.
3. `ResponseFormat` `Text` gives the answer in `Text`. `Json` also parses it into `Json`, checked
   against `JsonSchema` when one is given, so the next activities can read `Json.heat` and the like.
   An answer that isn't valid JSON fails with `llm_invalid_json`.
4. `Tools` lets the model use `ReadValues` (list and read reports, commands and variables) and
   `SendCommands`, which sends only the `AllowedCommands`, at most `MaxCommands` (3) of them, through
   the outbox like any command. `MaxToolCalls` (10, at most 50) and `TimeoutSeconds` (60, at most 300)
   bound the step.

Every run is recorded, with its tokens, on the **AI models** page. The prompt and the values the
model reads go to the provider, so prefer a local server for private data. A connection that is
disabled or deleted fails the step with `llm_connection_disabled` or `llm_unknown_connection`.

## Templates

[RIoT2.Elsa/templates](https://github.com/Revolutionized-IoT2/RIoT2.Elsa/tree/master/templates)
has two workflows to start from:

| File | What it does |
|---|---|
| `motion-light.json` | Motion turns a light on; it goes off five minutes after the last motion (Trigger, Compare, Output, Debounce) |
| `price-based-heater.json` | A heater goes off when the electricity price rises above 15 and on again when it falls below 10 (Trigger, Threshold, Output) |

1. Download the file. On the UI's **Workflows** page, choose **Import** and pick it.
2. Open the imported workflow. In each RIoT activity, choose your own report or command; the
   template's selections are placeholders.
3. Adjust the limits or the window, then **Publish**. A template imports as a draft, so nothing runs
   before you publish it.

The template's definition id is fixed, so importing it again adds a new version of that workflow;
export your changed workflow first to keep a copy of it.

## Troubleshooting

- A workflow doesn't start: check that it is published, that its trigger selects the right report
  and has *Starts the workflow* on, and the *Workflows* page (or the *System* page) for the engine's
  state.
- An activity fails with an incident (in the designer's **Runs** tab, under the run) when its settings are
  invalid: no report or command chosen, a timeout or window out of range, `Lower` above `Upper`, an
  invalid schedule, or a webhook URL that isn't http or https.
- Elsa logs (the orchestrator's log in the embedded mode) every schedule that fires (`Schedule 07:30 fired`), and a warning for a schedule that is
  invalid or needs the location.
