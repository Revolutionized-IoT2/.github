# Metrics

Applies to: Core, Orchestrator, Node, Elsa, InfluxDB connector, `deploy/`. Design:
[7.4](../design/operations.md) (decisions 3 and 4); as built:
[phase 4](../design/operations-as-built.md#as-built-phase-4-i22).

Every .NET service records these instruments with `System.Diagnostics.Metrics`. They cost nothing
until something listens. `AddRIoT2Telemetry()` (`RIoT2.Core.Hosting`) exports them over OTLP only
when `OTEL_EXPORTER_OTLP_ENDPOINT` is set ([env-vars.md](env-vars.md#shared-variables)), together
with ASP.NET Core's `http.server.*` and the .NET runtime's metrics. The resource has
`service.name` `riot2-<service>` (`riot2-orchestrator`, `riot2-node`, `riot2-elsa`,
`riot2-connector`), `service.namespace` `riot2` and the service's RIoT2 id as
`service.instance.id`.

## Names

- OpenTelemetry names are dotted (`riot2.reports.received`). Prometheus, through the collector in
  `deploy/compose.observability.yml`, replaces dots with underscores, adds `_total` to counters and
  `_seconds` for the unit `s`, and adds the resource attributes as labels (`service_name`,
  `service_instance_id`). The Prometheus column shows the result.
- Tag values are camelCase, as in JSON (`unknownCommand`, `running`).
- A new, renamed or removed instrument changes this file in the same change. The services' tests pin
  the names, and docs-check's `metrics` rule compares this file with the code and with the
  `riot2_*` queries of the Grafana dashboard (`deploy/grafana/dashboards/riot2-system.json`).

## MQTT client (meter `RIoT2.Mqtt`, every service)

| Name | Type | Tags | Prometheus | Meaning |
|---|---|---|---|---|
| `riot2.mqtt.connected` | Gauge | `client` | `riot2_mqtt_connected` | 1 while a started client is connected to the broker, 0 while it isn't |
| `riot2.mqtt.reconnects` | Counter | `client` | `riot2_mqtt_reconnects_total` | Connections after a client's first one |
| `riot2.mqtt.dropped` | Counter | `client` | `riot2_mqtt_dropped_total` | Outgoing messages dropped because the pending queue was full while the broker was unreachable (Core 1.3.0) |

## Orchestrator (meter `RIoT2.Orchestrator`)

| Name | Type | Tags | Prometheus | Meaning |
|---|---|---|---|---|
| `riot2.reports.received` | Counter | `node` | `riot2_reports_received_total` | Reports with a configured template |
| `riot2.reports.unknown_template` | Counter | `node` | `riot2_reports_unknown_template_total` | Reports dropped because no template has their id |
| `riot2.workflow.deliveries` | Counter | `outcome`: `delivered`, `failed`, `retry`, `expired` | `riot2_workflow_deliveries_total` | Workflow trigger delivery attempts and expiries |
| `riot2.outbox.pending` | Gauge | `kind`: `workflow`, `command` | `riot2_outbox_pending` | Pending outbox messages |
| `riot2.outbox.oldest_age_seconds` | Gauge (s) | `kind` | `riot2_outbox_oldest_age_seconds` | Age of the oldest pending message; 0 when none |
| `riot2.commands` | Counter | `outcome`: the final delivery status (`executed`, `duplicate`, `failed`, `unknownCommand`, `sent`, `expired`) | `riot2_commands_total` | Commands whose delivery became final |
| `riot2.command.latency` | Histogram (s) | `outcome` | `riot2_command_latency_seconds_bucket`, `_sum`, `_count` | From queueing a command to its final status |
| `riot2.nodes.online` | Gauge | `type`: `device`, `workflow`, `connector` (Orchestrator 1.17.0), … | `riot2_nodes_online` | Nodes that announced themselves online |
| `riot2.nodes.out_of_sync` | Gauge | `state`: `pending`, `failed` | `riot2_nodes_out_of_sync` | Online configured nodes that don't run their configuration ([desired state](configuration.md#desired-state)) |

## Node (meter `RIoT2.Node`, recorded in Core)

| Name | Type | Tags | Prometheus | Meaning |
|---|---|---|---|---|
| `riot2.node.devices` | Gauge | `state`: `unknown`, `stopped`, `initialized`, `running`, `error` | `riot2_node_devices` | Devices, by state; every state is reported, also at zero |
| `riot2.node.device_restarts` | Counter | none | `riot2_node_device_restarts_total` | Running devices stopped because their configuration changed or was removed. Zero across a reconnect or an unchanged configuration (backlog item 18) |
| `riot2.node.commands` | Counter | `outcome`: the command result status (`executed`, `failed`, `unknownCommand`, `rejected`, `duplicate`) | `riot2_node_commands_total` | Commands handled, with or without a correlation id |
| `riot2.node.reports.published` | Counter | none | `riot2_node_reports_published_total` | Reports published to the broker |
| `riot2.node.reports.dropped` | Counter | none | `riot2_node_reports_dropped_total` | Reports dropped because the publish queue was full |
| `riot2.node.config_applies` | Counter | `result`: `applied`, `failed`, `unchanged` | `riot2_node_config_applies_total` | Configuration commands handled; `unchanged` needed no work |

## Elsa (meter `RIoT2.Elsa`)

| Name | Type | Tags | Prometheus | Meaning |
|---|---|---|---|---|
| `riot2.workflow.triggers` | Counter | `result`: `received`, `duplicate`; `transport`: `grpc`, `http` | `riot2_workflow_triggers_total` | RIoT triggers; a `duplicate` was a redelivered message id and didn't run |
| `riot2.workflow.faults` | Counter | `definition` | `riot2_workflow_faults_total` | Workflow executions that ended faulted, by definition id |

## Connectors (meter `RIoT2.Connector`)

Recorded by the connector SDK (`RIoT2.Connector.Sdk`, Core 1.20.0; the spool from 1.21.0, [design 7.3](../design/connector-sdk.md)) for every connector; today the InfluxDB connector.

| Name | Type | Tags | Prometheus | Meaning |
|---|---|---|---|---|
| `riot2.connector.messages` | Counter | `type`: `report`, `command`; `result`: `queued`, `invalid`, `failed` (on receipt; `failed`: the queue was full, or the spool couldn't be written), `ignored` | `riot2_connector_messages_total` | Messages received; `ignored` is counted when the sink skips a queued message (no template or no writable value) |
| `riot2.connector.writes` | Counter (messages) | `outcome`: `written`, `retried`, `rejected`, `discarded` | `riot2_connector_writes_total` | Messages handed to the sink: `retried` per failed attempt (the batch is tried again), `rejected` dead-lettered (dropped without the spool), `discarded` at shutdown without the spool. Before Core 1.20.0: points, with `failed` |
| `riot2.connector.queue_depth` | Gauge | none | `riot2_connector_queue_depth` | Messages waiting in memory |
| `riot2.connector.spool_depth` | Gauge | none | `riot2_connector_spool_depth` | Messages waiting in the disk spool |
| `riot2.connector.spool_bytes` | Gauge (bytes) | none | `riot2_connector_spool_bytes` | Size of the spool's segment files; the limit is `RIOT2_CONNECTOR_SPOOL_MAX_MB` |
| `riot2.connector.spool_dropped` | Counter | `reason`: `size`, `age`, `unreadable` | `riot2_connector_spool_dropped_total` | Spooled messages lost: the oldest segment dropped at the size or age limit, or a line that can't be read |

## Prometheus exporter

Not instruments: the families `RIoT2.Connector.Prometheus` writes at `/metrics` (1.0.0, design 7.3 phase 4),
scraped by Prometheus as job `riot2-values` in `compose.observability.yml`. One series per report or
command template field, labelled `message` (`report`, `command`), `id`, `name`, `device`, `node` (the
template's) and `field` (`value`, or an entity's path such as `wind.speed`). A series not updated within
`RIOT2_PROMETHEUS_MAX_AGE_MINUTES` disappears. RIoT2.Tests pins the output (`Golden/prometheus-exposition.txt`).

| Name | Type | Meaning |
|---|---|---|
| `riot2_value` | Gauge | The latest value; booleans are 1 or 0. Text is not exported. |
| `riot2_value_timestamp_seconds` | Gauge | When it was reported (commands: received by the exporter), Unix seconds |

## Planned (not implemented)

- Firmware: heap, RSSI and uptime in an optional `diag` object of the node status, which the
  orchestrator turns into `riot2.firmware.*` gauges.
