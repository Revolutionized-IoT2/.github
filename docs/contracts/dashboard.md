# Dashboard and value schemas

Applies to: Core (models), Orchestrator (stores and serves them), UI (edits and shows them), device plugins
(declare value schemas), connectors (read them from the template listings).

Source of truth:

| Topic | Code |
|---|---|
| Models | `RIoT2.Core/src/Contracts/Models/DashboardConfiguration.cs`, `DashboardPage.cs`, `DashboardComponent.cs`, `DashboardElement.cs`, `ValueSchema.cs` |
| Ids on load and save | `RIoT2.Net.Orchestrator/Services/OrchestratorConfigurationService.cs` |
| Template listings | `RIoT2.Net.Orchestrator/Services/Templates/TemplateCatalog.cs` |

Templates and the rest of the node configuration: [configuration.md](configuration.md). Routes:
[http-api.md](http-api.md#dashboard-apidashboard). Golden files are in
[RIoT2.Core/contracts/golden](https://github.com/Revolutionized-IoT2/RIoT2.Core/blob/main/contracts/golden/README.md).

## Dashboard configuration

`GET /api/dashboard/configuration` returns the `DashboardConfiguration` (`Json.Serialize`), and the UI posts it back
to save it. `pages[]` hold `components[]` (cards: `name`, `description`, `icon`, `type`, `size`), which hold
`elements[]` (a report or command template by `id`, with `properties`). From Core 2.2.0 and Orchestrator 1.21.0
(all omitted when unset):

- `pages[].id`, `components[].id`: stable ids, like `elements[].id`. The orchestrator gives every page, card and
  element without an id a new GUID when it loads the dashboard (in memory) and when it saves it (stored), and never
  changes an existing id.
- `components[].kind`: the UI card kind, an open set (see [card kinds](#card-kinds-ui-1110)). The UI still writes
  the closest `type`, which readers that don't know the kind use.
- `components[].settings`: the card's own settings, an object defined by its kind. The orchestrator stores it as
  sent; element settings stay in `elements[].properties`.

Golden file: `http/dashboard-configuration-cards.json`. A card with the new members:

```json
{ "name": "Temperature", "description": "", "icon": "thermometer", "type": 5, "size": 3,
  "elements": [ { "name": "Temperature", "id": "e1", "reportTemplate": { "id": "r1" } } ],
  "id": "c1", "kind": "gauge", "settings": { "min": 0, "max": 40, "warning": 30, "critical": 35, "lowIsBad": false } }
```

### Card kinds (UI 1.11.0)

Each kind is a folder in RIoT2.UI's `src/dashboard/cards/`, which declares its settings and their defaults
([card kit guide](https://github.com/Revolutionized-IoT2/RIoT2.UI/blob/main/src/dashboard/README.md)). A new kind needs
no Core or orchestrator change. The UI gives a card saved without a `kind` the kind that replaces its `type`, and
stores it that way at the next save.

| `kind` | Card | `type` written | Replaces `type` |
|---|---|---|---|
| `sensor` | A reading with sparkline and trend | 5 (numeric value) | 5 |
| `gauge` | A value on a dial | 5 | |
| `entities` | A list of values, with switches | 5 | |
| `chart` | Line, bar, doughnut or pie (`settings.chartType`) | 1?4 | 1?4 |
| `buttons` | Tiles that toggle or send a value (`settings.layout`: `grid` or `row`) | 0 or 8 | 0, 8 |
| `switch` | On and off switches | 10 | 10 |
| `light` | Power, brightness and colour (elements with `properties.role`) | 10 | |
| `state` | One of several states | 9 | 9 |
| `motion` | Motion now and the last motion | 9 | |
| `image` | An image from a URL, with earlier ones | 6 | 6 |
| `activity` | True reports per period (the former timeline) | 7 | 7 |
| `markdown` | A note in Markdown | 6 | |
| `forecast` | A forecast series as bars or a line, with the value now (UI 1.13.0, [forecasts.md](forecasts.md)) | 1 or 2 | |

An element's `properties.member` names the member of an entity report it shows (before, `"{member}"` in
`properties.value`). Other string properties may still be `"{member}"`, read from the current report.

### Export file

*Import and export* in the dashboard editor writes the definition without reports:
`{ "format": "riot2-dashboard", "version": 1, "exportedAt": "?", "dashboard": { ? } }`. Its templates are
`{ id, name, node, device }`; an import binds them by `id`, else by node, device and name. A stored
`DashboardConfiguration` imports too.

## Value schema

From Core 2.2.0 a report or command template can describe its value with `schema` (`ValueSchema`), a subset of
JSON Schema with the same keywords plus `unit` and `semantic`. The device plugin declares it (or the user edits it);
the orchestrator stores it with the node configuration and passes it on in the template listings and the
dashboard's templates. The UI builds inputs and picks dashboard cards from it. Every member is optional and
omitted when unset:

```json
"schema": {
  "type": "object",
  "properties": {
    "temperature": { "type": "number", "unit": "°C", "semantic": "temperature", "minimum": -40, "maximum": 85 },
    "mode": { "type": "string", "title": "Mode", "enum": ["auto", "eco", "off"] },
    "history": { "type": "array", "items": { "type": "number", "unit": "°C" } }
  }
}
```

| Member | Meaning |
|---|---|
| `type` | `boolean`, `number`, `integer`, `string`, `object` (an entity) or `array` |
| `title`, `description` | Label and help text |
| `unit` | For example `°C`, `%`, `W`, `kWh`, `lx` |
| `semantic` | What the value means, an open set (`ValueSemantics`): `temperature`, `humidity`, `pressure`, `illuminance`, `power`, `energy`, `voltage`, `current`, `battery`, `co2`, `motion`, `occupancy`, `contact`, `door`, `window`, `light`, `switch`, `brightness`, `color`, `colorTemperature`, `image`, `text`, and `forecast` (Core 2.3.0: the value is a forecast series, [forecasts.md](forecasts.md)). Readers ignore one they don't know. |
| `minimum`, `maximum`, `multipleOf` | Range (inclusive) and step of a number |
| `enum` | The allowed values |
| `properties` | An entity's members, by name (camelCase, like every dictionary key), each a value schema |
| `items` | The value schema of an array's items |
| `readOnly` | The UI shows the value but offers no input |

Plugins build the common shapes with `ValueSchema.Boolean`, `Number`, `Integer`, `Text`, `Entity`,
`ArrayOf` and `Forecast` (2.3.0). The connector SDK reads it into `ConnectorTemplate.Schema`. Variables have none. Golden file:
`http/templates-report-schema.json`.
