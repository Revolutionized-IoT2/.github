# Environment variables, ports, volumes and images

Applies to: every deployable component.
Source of truth: the configuration services that read these variables:

| Component | Code |
|---|---|
| Orchestrator | `RIoT2.Net.Orchestrator/Services/OrchestratorConfigurationService.cs` |
| Node | `RIoT2.Net.Node/Services/NodeEnvironmentValidator.cs`, `ConfigurationService.cs` |
| Elsa | `RIoT2.Elsa/RIoT2.Elsa.Server/RIoT/Services/RIoTConfigurationService.cs`, `WorkflowEndpointConfiguration.cs`, `Program.cs` |
| InfluxDB connector | `RIoT2.Connector.InfluxDB/Services/ConnectorConfigurationService.cs` |
| UI | `RIoT2.UI/Dockerfile`, `entrypoint.sh` |

Ports and users come from each repository's `Dockerfile`. Image names come from the
`.github/workflows` files.

Rules:

- Images contain no IDs, IPs or credentials. Required variables have no default. A .NET
  service with a missing or invalid required value logs a critical error and exits.
- Each id must be unique across the whole system (a GUID is recommended), because it is also the
  MQTT client id and the `{id}` in topics ([mqtt-topics.md](mqtt-topics.md)).
- URL variables must be absolute `http`/`https` URLs that are reachable **from other
  containers and devices**, not `localhost`.

## Shared variables

| Variable | Used by | Required | Notes |
|---|---|---|---|
| `RIOT2_MQTT_IP` | Orchestrator, Node, Elsa, connector | Yes | Broker host name or IP, without scheme or port. Port 1883 is fixed in .NET (`MqttClient`). |
| `RIOT2_MQTT_USERNAME` | Orchestrator, Node, Elsa, connector | No | Leave empty for anonymous brokers. |
| `RIOT2_MQTT_PASSWORD` | Orchestrator, Node, Elsa, connector | No | |
| `TZ` | All images | No | Image default `Europe/Helsinki`. Not read by code. |
| `ASPNETCORE_ENVIRONMENT` | .NET images | No | Image default `Production`. Elsa enforces the signing key outside `Development`. |

## Per component

### Orchestrator

| Variable | Required | Validation |
|---|---|---|
| `RIOT2_ORCHESTRATOR_ID` | Yes | Non-empty. Also the MQTT client id. |
| `RIOT2_ORCHESTRATOR_URL` | Yes | Absolute http/https. Sent to nodes as `ConfigurationCommand.apiBaseUrl`, so nodes and firmware must be able to reach it (e.g. `http://192.168.0.32` when publishing `-p 80:8080`). |

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
| `RIOT2_WORKFLOW_GRPC_PORT` | No | Default `5003`, range 1–65535. Local plaintext HTTP/2 listener. `Kestrel:Endpoints:WorkflowGrpc:Url` overrides it. |
| `ELSA_IDENTITY_SIGNING_KEY` | Yes, outside Development | Strong secret, e.g. `openssl rand -base64 48`. In Development a random key is generated on each start. |
| `Http__*` | No | Bound to Elsa's `Http` options section. |

### InfluxDB connector

| Variable | Required | Validation / default |
|---|---|---|
| `RIOT2_CONNECTOR_ID` | Yes | Non-empty. MQTT client id. |
| `RIOT2_INFLUXDB_HOST` | Yes | Absolute http/https |
| `RIOT2_INFLUXDB_TOKEN` | Yes | Non-empty |
| `RIOT2_INFLUXDB_BUCKET` | Yes | Non-empty |
| `RIOT2_INFLUXDB_ORGANIZATION` | Yes | Non-empty |
| `RIOT2_HANDLE_COMMANDS` | No | `true` subscribes to `riot2/node/+/command` as well. Anything else means `false`. |

### UI

| Variable | Required | Notes |
|---|---|---|
| `VITE_MQTT_SERVER` | Yes in practice | Broker host for the browser. Image default `localhost`. The browser connects to `ws://<host>:9001/`, so the broker needs a WebSocket listener on 9001. |
| `VITE_MQTT_USER`, `VITE_MQTT_PASSWORD` | No | Empty values log a warning. They are visible to anyone who can open the UI ([ADR 0002](../adr/0002-isolated-network-security-model.md)). |
| `ROOT_DIR`, `TEMPLATE_DIR`, `SKIP_NGINX` | No | Entrypoint internals, used by tests. |

The values are written into the served JavaScript by `entrypoint.sh` on every container start,
from pristine template copies, so a restart is enough to change them.

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

## Ports, volumes and images

| Component | Image (`ghcr.io/revolutionized-iot2/…`) | Container port(s) | Runs as | Persistent paths |
|---|---|---|---|---|
| Orchestrator | `riot2-orchestrator:latest`, `:<tag>` | 8080 | `$APP_UID` (1654) | `/app/StoredObjects` (configuration), `/app/Logs`, `/app/MatterCredentials`, `/app/Data` |
| Node | `riot2-node:latest`, `:<tag>`; ARM64: `:latest-arm64v8`, `:<tag>-arm64v8` | 80 | root (no `USER` directive) | `/app/Data`, `/app/Logs`, `/app/Plugins` |
| Elsa | `riot2-elsa:latest`, `:<tag>` | 8080 (web/Studio), 5003 (gRPC) | `app` (1654) | `/app/Data` (`elsa.sqlite.db`) |
| InfluxDB connector | `riot2-influxdb:latest`, `:<tag>` | 8080 | `app` (1654) | none |
| UI | `riot2-ui:latest`, `:<tag>` | 80 (nginx) | nginx default | none |

- No image declares `VOLUME`. Mount the paths above yourself.
- Host directories bind-mounted into non-root containers must be writable by UID 1654
  (`sudo chown -R 1654:1654 <dir>`).
- Matter commissioning needs `--network host` (mDNS, IPv6). With host networking, the non-root
  orchestrator cannot bind ports below 1024, so keep 8080.
- Raspberry Pi nodes that use GPIO, I2C or Bluetooth run with `--privileged` and
  `-v /var/run/dbus:/var/run/dbus:ro`.
- MQTT broker: TCP 1883 for .NET and firmware, WebSocket 9001 for the UI, and 8883 for firmware
  TLS.

## Planned (not implemented)

`RIOT2_SECURITY_MODE=off|audit|on` (PLATFORM-REVIEW design 7.5), and `RIOT2_OUTBOX_WORKFLOW_TTL`
/ `RIOT2_OUTBOX_COMMAND_TTL` (design 7.1). No code reads them yet.
