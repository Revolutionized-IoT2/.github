# Environment variables

Applies to: every deployable component.
Source of truth: the options type that maps and validates each service's variables (plan
[M4](../plans/m04-typed-configuration.md)). Nothing else in a .NET service reads the environment.

| Component | Code |
|---|---|
| Shared MQTT variables | `RIoT2.Core/src/Mqtt/Configuration/MqttOptions.cs` (Core 1.2.0) |
| Shared security variables | `RIoT2.Core/src/Mqtt/Configuration/SecurityOptions.cs` (Core 1.18.0) |
| Orchestrator | `RIoT2.Net.Orchestrator/Services/OrchestratorOptions.cs` |
| Node | `RIoT2.Net.Node/Services/NodeOptions.cs` |
| Elsa | `RIoT2.Elsa/RIoT2.Elsa.Server/RIoT/Services/WorkflowOptions.cs` (the gRPC listener: `WorkflowEndpointConfiguration.cs`) |
| Connectors | SDK `RIoT2.Core/Connector/ConnectorOptions.cs`, plus `InfluxConnectorOptions.cs` (InfluxDB) and `PrometheusExporterOptions.cs` (Prometheus) |
| UI | `RIoT2.UI/Dockerfile`, `entrypoint.sh` |

Ports, users, volumes and images: [images.md](images.md).

Rules:

- Images contain no IDs, IPs or credentials. Required variables have no default. A .NET
  service reads and validates every variable at startup. If any is missing or invalid, it logs one
  critical message that lists them all and exits:
  `Invalid node configuration: RIOT2_NODE_ID is required; RIOT2_NODE_URL must be an absolute http or https URL.`
- The .NET services read the variables through the host configuration, so a value can also come
  from `appsettings.json` or a `--RIOT2_NODE_ID=value` command-line argument. Environment variables
  override `appsettings.json`; the command line overrides both.
- Each id must be unique across the whole system (a GUID is recommended), because it is also the
  MQTT client id and the `{id}` in topics ([mqtt-topics.md](mqtt-topics.md)).
- URL variables must be absolute `http`/`https` URLs that are reachable **from other
  containers and devices**, not `localhost`.

## Shared variables

| Variable | Used by | Required | Notes |
|---|---|---|---|
| `RIOT2_MQTT_IP` | Orchestrator, Node, Elsa, connector | Yes | Broker host name or IP, without scheme or port. |
| `RIOT2_MQTT_PORT` | Orchestrator, Node, Elsa, connector | No | Broker TCP port, a whole number from 1 to 65535; default 1883 (Core 1.3.0). |
| `RIOT2_MQTT_USERNAME` | Orchestrator, Node, Elsa, connector | No | Leave empty for anonymous brokers. |
| `RIOT2_MQTT_PASSWORD` | Orchestrator, Node, Elsa, connector | No | |
| `RIOT2_MQTT_TLS` | Orchestrator, Node, Elsa, connector | No | `true`: TLS, default port 8883; the broker's certificate must match `RIOT2_MQTT_IP` and chain to a trusted CA. Works in any security mode (Core 1.18.0). |
| `RIOT2_MQTT_CA_FILE` | Orchestrator, Node, Elsa, connector | No | A private CA's certificate file (PEM or DER) the broker's must chain to. Needs `RIOT2_MQTT_TLS=true`; must exist. |
| `RIOT2_SECURITY_MODE` | Orchestrator, Node, Elsa, connector | No | `off` (default), `audit` or `on` ([design 7.5](../design/security-mode.md)). Only `off` is accepted yet (I34: Orchestrator 1.15.0, Node 1.13.0, Elsa 1.8.0, connector 1.7.0); nothing is enforced. |
| `RIOT2_SECURITY_FEATURES` | Orchestrator, Node, Elsa, connector | No | `all` (default) or a subset of `api`, `realtime`, `mqtt`, `endpoints`, `signing`, `secrets`, `outbound`. Ignored while `off`. |
| `RIOT2_API_KEY` | Orchestrator, Node, Elsa, connector | No | The service's key, sent in `X-RIoT2-Key` on its calls to other RIoT2 services, never to devices. Unchecked while `off`. |
| `RIOT2_CORS_ORIGINS` | Orchestrator, Elsa | No | Browser origins (`http://riot2.lan:8080`), comma-separated, allowed when `api` is on. Any origin while `off`. |
| `RIOT2_LOG_FORMAT` | Orchestrator, Node, Elsa, connector | No | `text` (default) or `json`, any case: readable lines or compact JSON (`@t`, `@m`, `@l`, `Service`, `SourceContext`, `CorrelationId`, …) on the console and in `Logs/RIoT2.log` ([design 7.4](../design/operations.md)). Core 1.9.0. |
| `RIOT2_LOG_LEVEL` | Orchestrator, Node, Elsa, connector | No | The lowest level written: `Trace`, `Debug`, `Information` (default), `Warning`, `Error` or `Critical`, any case. `Microsoft.*` and `System.*` start at `Warning` unless this is higher (`Microsoft.Hosting.Lifetime` at `Information`). Replaces the `Logging` section the images' `appsettings.json` had. |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | Orchestrator, Node, Elsa, connector | No | OTLP collector (absolute `http`/`https` URL), for example `http://otel-collector:4317`. Unset or empty: nothing is exported. Set: the [metrics](metrics.md) go over OTLP (gRPC by default; the SDK reads the other `OTEL_EXPORTER_OTLP_*` variables too). Core 1.10.0. |
| `OTEL_METRIC_EXPORT_INTERVAL` | Orchestrator, Node, Elsa, connector | No | Milliseconds between metric exports, read by the OpenTelemetry SDK; default 60000 (compose: 15000). |
| `RIOT2_TRACING` | Orchestrator, Node, Elsa, connector | No | `true` also exports traces; needs `OTEL_EXPORTER_OTLP_ENDPOINT`. Default `false`; anything but `true`/`false` stops the start. |
| `TZ` | All images | No | Image default `Europe/Helsinki`. Not read by code. |
| `ASPNETCORE_ENVIRONMENT` | .NET images | No | Image default `Production`. Elsa enforces the signing key outside `Development`. |

## Per component

### Orchestrator

| Variable | Required | Validation |
|---|---|---|
| `RIOT2_ORCHESTRATOR_ID` | Yes | Non-empty. Also the MQTT client id. |
| `RIOT2_ORCHESTRATOR_URL` | Yes | Absolute http/https. Sent to nodes as `ConfigurationCommand.apiBaseUrl`, so nodes and firmware must reach it. |
| `RIOT2_OUTBOX_WORKFLOW_TTL` | No | Seconds a workflow trigger waits in the outbox for delivery before it expires; a whole number from 1 to 86400, default 300 (Orchestrator 1.3.0, [design 7.1](../design/reliable-delivery.md)). |
| `RIOT2_OUTBOX_COMMAND_TTL` | No | Seconds a command waits in the outbox for its node and its answer before it expires, unless the request sets `ttlSeconds`; a whole number from 1 to 86400, default 30 (Orchestrator 1.4.0, [http-api.md](http-api.md#commands-commandscontroller-apiv2commands)). |
| `RIOT2_BACKUP_SCHEDULE` | No | When to write a configuration backup to `/app/Backups`: a Quartz cron expression with seconds (`0 0 3 * * ?` is 03:00 every day) in `TZ`. Unset or empty: off ([backup-and-restore.md](../guides/backup-and-restore.md)). |
| `RIOT2_BACKUP_RETENTION` | No | How many backups `/app/Backups` keeps, scheduled and pre-restore together; the oldest are deleted. 1–365, default 7 (Orchestrator 1.7.0). |

### Node

| Variable | Required | Validation |
|---|---|---|
| `RIOT2_NODE_ID` | Yes | Non-empty. Must match the node id configured in the UI. |
| `RIOT2_NODE_URL` | Yes | Absolute http/https. Advertised as `nodeBaseUrl`. The orchestrator calls it. |

### Elsa

| Variable | Required | Validation / default |
|---|---|---|
| `RIOT2_WORKFLOW_ID` | Yes | Non-empty |
| `RIOT2_WORKFLOW_URL` | Yes | Absolute http/https. Studio/web URL as reachable from outside the container. |
| `RIOT2_WORKFLOW_GRPC_URL` | Yes | Absolute http/https. Externally reachable gRPC URL, **including** the published port (e.g. `http://192.168.0.32:5003`). |
| `RIOT2_WORKFLOW_GRPC_PORT` | No | Default `5003`, a whole number from 1 to 65535. Local plaintext HTTP/2 listener. `Kestrel:Endpoints:WorkflowGrpc:Url` overrides it. |
| `ELSA_IDENTITY_SIGNING_KEY` | Yes, outside Development | Strong secret, e.g. `openssl rand -base64 48`. In Development a random key is generated on each start. Reported together with the other settings. |
| `Http__*` | No | Bound to Elsa's `Http` options section. |

### Connectors

Every connector (connector SDK) reads these:

| Variable | Required | Validation / default |
|---|---|---|
| `RIOT2_CONNECTOR_ID` | Yes | Non-empty. MQTT client id. |
| `RIOT2_CONNECTOR_NAME` | No | The name in the UI; default `InfluxDB`, `Prometheus` or `Home Assistant` (Core 1.22.0). |
| `RIOT2_CONNECTOR_URL` | No | Absolute http/https, reachable by the orchestrator, which shows the connector's `/health` in the UI. |
| `RIOT2_INFLUXDB_HOST` | InfluxDB: yes | Absolute http/https |
| `RIOT2_INFLUXDB_TOKEN`, `RIOT2_INFLUXDB_BUCKET`, `RIOT2_INFLUXDB_ORGANIZATION` | InfluxDB: yes | Non-empty |
| `RIOT2_HANDLE_COMMANDS` | No | `true` (any case) subscribes to `riot2/node/+/command` as well. Anything else means `false`. |
| `RIOT2_CONNECTOR_SPOOL` | No | Default `true`: messages wait in `/app/Data/spool` while InfluxDB is down, and rejected batches go to its `dead-letter.jsonl` (1.9.0). `false`: memory only. |
| `RIOT2_CONNECTOR_SPOOL_MAX_MB` | No | 1–100000, default 100; beyond it the oldest are dropped. |
| `RIOT2_CONNECTOR_SPOOL_MAX_AGE_DAYS` | No | 1–365, default 7; older ones are dropped. |
| `RIOT2_PROMETHEUS_MAX_AGE_MINUTES` | No | Prometheus exporter: 1–10080, default 60; a value not sent again within it leaves `/metrics`. The exporter has no spool. |
| `RIOT2_HA_MQTT_IP` | No | Home Assistant connector (1.0.0): the broker Home Assistant uses; empty uses the RIoT2 broker. With it: `RIOT2_HA_MQTT_PORT` (1883, 8883 with TLS), `RIOT2_HA_MQTT_USERNAME`, `RIOT2_HA_MQTT_PASSWORD`, `RIOT2_HA_MQTT_TLS`, `RIOT2_HA_MQTT_CA_FILE` (needs TLS, must exist). |
| `RIOT2_HA_DISCOVERY_PREFIX`, `RIOT2_HA_TOPIC_PREFIX` | No | Home Assistant connector: the discovery prefix (default `homeassistant`) and the prefix of its states, availability and commands (default `riot2/ha`; a second connector on the same broker needs its own); no wildcards. |
| `RIOT2_HA_COMMAND_TTL_SECONDS` | No | Home Assistant connector: 1–86400, default 60; the time-to-live of a command from Home Assistant. The connector has no spool. |

### UI

| Variable | Required | Notes |
|---|---|---|
| `VITE_MQTT_SERVER` | Yes in practice | Broker host for the browser. Image default `localhost`. The browser connects to `ws://<host>:9001/`, so the broker needs a WebSocket listener on 9001. |
| `VITE_MQTT_USER`, `VITE_MQTT_PASSWORD` | No | Empty values log a warning. They are visible to anyone who can open the UI ([ADR 0002](../adr/0002-isolated-network-security-model.md)). |
| `ORCHESTRATOR_UPSTREAM` | No | `http(s)://host[:port]`, e.g. `http://orchestrator:8080` (UI 1.7.0). nginx proxies `/api/` and `/realtime` there and the UI calls the API on its own origin. Empty: both answer 404, and the UI uses the URL in its configuration command. |
| `ROOT_DIR`, `TEMPLATE_DIR`, `PROXY_CONF`, `SKIP_NGINX` | No | Entrypoint internals, used by tests. |

The values are written into the served JavaScript and the proxy configuration by `entrypoint.sh`
on every container start, from pristine template copies, so a restart is enough to change them.

### Compose install (`deploy/`)

The compose files in [deploy/](../../deploy/) read these from `deploy/.env`, in addition to the
service variables above. [.env.example](../../deploy/.env.example) lists them all; docs-check
fails if a compose file reads a variable that it doesn't list. Compose builds every service URL
from `RIOT2_HOST` and the host ports, and points the services at the broker by its service
name `mosquitto`.

| Variable | Required | Notes |
|---|---|---|
| `RIOT2_HOST` | Yes | LAN address of the Docker host. Becomes the host part of `RIOT2_ORCHESTRATOR_URL`, `RIOT2_NODE_URL`, `RIOT2_WORKFLOW_URL`, `RIOT2_WORKFLOW_GRPC_URL` and `VITE_MQTT_SERVER`. With `compose.node-raspi.yml`, the Pi's address. |
| `RIOT2_MQTT_USERNAME`, `RIOT2_MQTT_PASSWORD` | Yes | Also create the broker account: `deploy/mosquitto/start.sh` writes the password file on every start. The UI gets them as `VITE_MQTT_USER` and `VITE_MQTT_PASSWORD`. |
| `RIOT2_ORCHESTRATOR_HOST_PORT` | No | Default 8080. Keep 8080 with `compose.matter.yml`. |
| `RIOT2_NODE_HOST_PORT` | No | Default 8081 (80 in `compose.node-raspi.yml`). |
| `RIOT2_ELSA_HOST_PORT`, `RIOT2_ELSA_GRPC_HOST_PORT` | No | Defaults 8082 and 5003. |
| `RIOT2_UI_HOST_PORT` | No | Default 80. |
| `RIOT2_NODE_PLUGINS` | No | Host folder mounted at the node's `/app/Plugins`, default `./plugins`. |
| `RIOT2_SECURITY_MODE` | No | Passed to every .NET service; default `off`, the only mode this release accepts. |
| `RIOT2_ORCHESTRATOR_API_KEY`, `RIOT2_ELSA_API_KEY`, `RIOT2_NODE_API_KEY`, `RIOT2_CONNECTOR_API_KEY`, `RIOT2_PROMETHEUS_EXPORTER_API_KEY` | No | Each service's `RIOT2_API_KEY`; empty sends none. |
| `RIOT2_INFLUXDB_ADMIN_USERNAME`, `RIOT2_INFLUXDB_ADMIN_PASSWORD` | Password yes, with `compose.influx.yml` | InfluxDB's first-start admin login (default user `admin`; the password needs at least 8 characters). `RIOT2_INFLUXDB_TOKEN`, `_ORGANIZATION` and `_BUCKET` set up InfluxDB on its first start, and the connector and Grafana use them too. |
| `RIOT2_GRAFANA_ADMIN_PASSWORD` | Yes, with `compose.influx.yml` | Grafana's `admin` password. |
| `RIOT2_INFLUXDB_HOST_PORT`, `RIOT2_GRAFANA_HOST_PORT` | No | Defaults 8086 and 3000. `compose.observability.yml` uses the Grafana port and password too. |
| `RIOT2_OTLP_HOST_PORT`, `RIOT2_PROMETHEUS_HOST_PORT` | No | `compose.observability.yml`: the collector's OTLP gRPC port (default 4317, for services on other hosts) and Prometheus (default 9090). |
| `RIOT2_METRICS_RETENTION` | No | How long Prometheus keeps the metrics (`compose.observability.yml`); default `15d`. |
| `RIOT2_PROMETHEUS_MAX_AGE_MINUTES` | No | The exporter in `compose.observability.yml`; default 60. |
| `RIOT2_HA_*`, `RIOT2_HOMEASSISTANT_API_KEY` | No | `compose.homeassistant.yml`: the Home Assistant connector's settings above, and its `RIOT2_API_KEY`. |

Compose sets the UI's `ORCHESTRATOR_UPSTREAM` to `http://orchestrator:8080`, so the browser uses
the `/api` proxy. Compose gives the ids defaults (`riot2-orchestrator`, `riot2-elsa`, `riot2-node-1`,
`riot2-influxdb`, `riot2-prometheus-exporter`, `riot2-homeassistant`); they only need to be unique on the broker.

### Firmware (M5Core2, M5Dial)

Firmware uses no environment variables. Settings are entered in the provisioning portal and
stored in ESP32 NVS (namespace `riot2node`):

| Setting | NVS key | Notes |
|---|---|---|
| Node id | `id` | Required |
| Name | `name` | Board-specific default |
| Wi-Fi SSID / password | `ssid` / `pass` | SSID required |
| MQTT URL / user / password | `mqttUrl` / `mqttUser` / `mqttPass` | URL required |
| MQTT over TLS | `mqttTls` | Default `false`; port 8883 |
| Vibration | `vibrate` | Default `true` |

### Development-only

| Variable | Component |
|---|---|
| `CONTROLLER_DIAGNOSTICS` | RIoT2.Matter Controller |
| `ONOFF_DIAGNOSTICS` | RIoT2.Matter OnOffSample |

`Properties/launchSettings.json` files contain local development values. Don't copy them into
documentation or images.

## Planned (not implemented)

The security modes `audit` and `on`, and the settings their features add (for example
`RIOT2_BOOTSTRAP_ADMIN_PASSWORD`, `RIOT2_PLUGIN_TRUSTED_KEYS`): increments I49–I54, only when
needed ([design 7.5](../design/security-mode.md)).
