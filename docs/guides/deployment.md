# Deployment variations and operations

Applies to: operators extending the basic installation from [getting-started.md](getting-started.md).
Every variable, port and volume is listed in [env-vars.md](../contracts/env-vars.md). The compose
files are in [deploy/](../../deploy/); run the commands below in that folder.

## Several hosts or other ports

Each service can run on its own host. The rules don't change:

- Every `*_URL` variable must be the address **as reachable from the other participants**,
  including the published port. Orchestrator, Node and Elsa advertise these URLs over MQTT, and
  the others call them. The compose files build them from `RIOT2_HOST` and the
  `RIOT2_*_HOST_PORT` values in `.env`.
- Container ports are fixed:

  | Component | Container port |
  |---|---|
  | Orchestrator | 8080 |
  | Node | 80 |
  | Elsa | 8080 (web) and 5003 (gRPC) |
  | InfluxDB connector | 8080 |
  | UI | 8080 (80 before UI 1.1.0) |

  Publish them as you like, for example `-p 80:8080` for an orchestrator on its own host, with
  `RIOT2_ORCHESTRATOR_URL=http://<orchestrator-host>`.
- All participants need the broker on 1883, and browsers need it on 9001 (WebSocket).
- Without compose, take each service's image, variables, ports and volumes from
  `deploy/docker-compose.yml`, and replace the broker name `mosquitto` with the broker's address.
  A host directory mounted into a non-root container (orchestrator, Elsa) must be owned by UID 1654.

## Raspberry Pi node

Use the ARM64 node image and the Raspberry Pi plugins
([RIoT2.Net.RasPi.Devices](https://github.com/Revolutionized-IoT2/RIoT2.Net.RasPi.Devices): GPIO,
I2C, Bluetooth, serial, Z-Wave). You can use them instead of, or alongside, the default plugin
package.

1. Install Raspberry Pi OS (64-bit) and
   [Docker for Debian](https://docs.docker.com/engine/install/debian/).
2. Copy `deploy/` to the Pi, and copy the plugin files into `deploy/plugins`.
3. Create a `.env` on the Pi with the variables from the "Raspberry Pi node" section of
   `.env.example`: the Pi's address as `RIOT2_HOST`, the broker host as `RIOT2_MQTT_IP`, the
   broker account, a `RIOT2_NODE_ID` of its own, and `RIOT2_NODE_HOST_PORT=80`.
4. Start the node: `docker compose -f compose.node-raspi.yml up -d --wait`. It runs privileged
   (hardware access) with the host's D-Bus mounted (Bluetooth).

Check it with `docker compose -f compose.node-raspi.yml logs node`.

## ESP32 nodes (M5Stack Core2, M5Dial)

These are firmware nodes with a screen:
[RIoT2.Ard.M5Core2.Node](https://github.com/Revolutionized-IoT2/RIoT2.Ard.M5Core2.Node) (touch)
and [RIoT2.Ard.M5Dial.Node](https://github.com/Revolutionized-IoT2/RIoT2.Ard.M5Dial.Node) (rotary
dial).

- Build and flash them with PlatformIO, as described in each repository's README.
- On first boot they open a Wi-Fi setup portal, where you enter Wi-Fi, MQTT and the node id.
- After that they join the bus like any node. Create them in the UI with
  [first-configuration.md](first-configuration.md) and choose their views from the device list.
- They use plain MQTT on 1883, or TLS on 8883 if your broker has a TLS listener
  (`deploy/mosquitto/mosquitto.conf` says how to add one). They must be able to reach
  `RIOT2_ORCHESTRATOR_URL`.
- Firmware updates over the air use the reserved command `system.ota`. Since firmware 0.2.0 a bad
  image rolls back to the previous one by itself: keep the orchestrator reachable during an update,
  because the new image must fetch its configuration within 3 minutes to stay.

## Time-series storage: InfluxDB and Grafana

[RIoT2.Connector.InfluxDB](https://github.com/Revolutionized-IoT2/RIoT2.Connector.InfluxDB) writes
every report (and optionally every command) to InfluxDB 2. Number and boolean values are written
directly; entity values are flattened into one field per leaf. Its README describes the point
schema for Grafana queries.

Fill in `RIOT2_INFLUXDB_TOKEN` (`openssl rand -hex 32`), `RIOT2_INFLUXDB_ADMIN_PASSWORD` and
`RIOT2_GRAFANA_ADMIN_PASSWORD` in `.env`, then add the InfluxDB file:

```bash
docker compose -f docker-compose.yml -f compose.influx.yml up -d --wait
```

To leave out the `-f` options in later commands, add
`COMPOSE_FILE=docker-compose.yml:compose.influx.yml` to `.env`. List a
`docker-compose.override.yml` there too, if you have one.

- InfluxDB creates the organization, bucket and token on its first start (port 8086).
- Grafana (port 3000, user `admin`) comes with the InfluxDB data source "RIoT2 InfluxDB" (Flux).
- `RIOT2_HANDLE_COMMANDS=true` also writes every command.
- To use an existing InfluxDB instead, run only the connector, with `RIOT2_INFLUXDB_HOST` pointing
  at it.
- If InfluxDB is unreachable, the connector loses those points: there is no spool yet
  ([design 7.3](../design/connector-sdk.md)).

## Mobile app

[RIoT2.Mobile](https://github.com/Revolutionized-IoT2/RIoT2.Mobile) (Android, Windows) shows the
UI's dashboard in a WebView, and receives Firebase push notifications on the topics `alerts` and
`notifications`.

- It needs your own Firebase project. Restrict the API key to the app.
- Point it at the UI's URL from its Settings screen.

## Matter (Apple Home, Google Home, Amazon Alexa)

The orchestrator contains a Matter bridge
([RIoT2.Matter](https://github.com/Revolutionized-IoT2/RIoT2.Matter)) that exposes RIoT2 devices
to Matter controllers.

- Matter discovery needs mDNS and IPv6, so the orchestrator runs on the host's network:
  `docker compose -f docker-compose.yml -f compose.matter.yml up -d --wait`. It then listens on
  the host's port 8080 directly (a non-root process can't bind ports below 1024), so keep
  `RIOT2_ORCHESTRATOR_HOST_PORT=8080`.
- The fabric credentials are in the `riot2_orchestrator-matter` volume (`/app/MatterCredentials`).
  Back it up, and keep it secret.
- Enable and commission the bridge on the UI's **Matter** page (QR code). Which devices are
  bridged is declared by the device plugins (`matterEndpoints`).

## Operations

| Task | How |
|---|---|
| Health | `docker compose ps` shows each service's Docker health check. Behind it is `GET /health` on orchestrator, node, Elsa and connector (Elsa and connector also `/healthz`). The orchestrator's and the node's health include their MQTT connection. |
| Logs | `docker compose logs <service>`. Orchestrator and node also write daily files to `/app/Logs` (volumes `riot2_orchestrator-logs`, `riot2_node-logs`). |
| Back up | Orchestrator `/app/StoredObjects` (all configuration) and `/app/MatterCredentials`, Elsa `/app/Data` (workflows, SQLite), node `/app/Data`. All of them can contain secrets. |
| Update plugins | Replace the files in `deploy/plugins` and `docker compose restart node`. Or set the node's **Plugin package Url**: the node downloads the zip and installs it on its next restart. That install replaces the whole `Plugins/` folder. |
| Update images | Read [upgrading.md](upgrading.md) first. Release and update the Node image and the plugin package together. |
| Time zone | `TZ` in `.env` (default `Europe/Helsinki`). |

Structured logs, metrics and a backup command are planned in
[design 7.4](../design/operations.md).
