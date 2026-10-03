# Deployment variations and operations

Applies to: operators extending the basic installation from [getting-started.md](getting-started.md).
Every variable, port and volume is listed in [env-vars.md](../contracts/env-vars.md).

## Several hosts or default ports

Each container can run on its own host. The rules don't change:

- Every `*_URL` variable must be the address **as reachable from the other participants**,
  including the published port. Orchestrator, Node and Elsa advertise these URLs over MQTT, and
  the others call them.
- Container ports are fixed:

  | Component | Container port |
  |---|---|
  | Orchestrator | 8080 |
  | Node | 80 |
  | Elsa | 8080 (web) and 5003 (gRPC) |
  | InfluxDB connector | 8080 |
  | UI | 80 |

  Publish them as you like, for example `-p 80:8080` for an orchestrator on its own host, with
  `RIOT2_ORCHESTRATOR_URL=http://<orchestrator-host>`.
- All participants need the broker on 1883, and browsers need it on 9001 (WebSocket).

## Raspberry Pi node

Use the ARM64 node image and the Raspberry Pi plugins
([RIoT2.Net.RasPi.Devices](https://github.com/Revolutionized-IoT2/RIoT2.Net.RasPi.Devices): GPIO,
I2C, Bluetooth, serial, Z-Wave). You can use them instead of, or alongside, the default plugin
package.

1. Install Raspberry Pi OS (64-bit) and
   [Docker for Debian](https://docs.docker.com/engine/install/debian/).
2. Create `/srv/riot2/node/{Data,Logs,Plugins}` and copy the plugin files into `Plugins/`.
3. Start the node. Hardware access needs `--privileged`, and Bluetooth needs D-Bus:

```bash
docker run -d --name riot2-node --restart unless-stopped -p 80:80 --privileged \
  -v /srv/riot2/node/Data:/app/Data \
  -v /srv/riot2/node/Logs:/app/Logs \
  -v /srv/riot2/node/Plugins:/app/Plugins \
  -v /var/run/dbus:/var/run/dbus:ro \
  -e RIOT2_NODE_ID=<node-guid> -e RIOT2_NODE_URL=http://<pi-host> \
  -e RIOT2_MQTT_IP=<broker-host> -e RIOT2_MQTT_USERNAME=<mqtt-user> -e RIOT2_MQTT_PASSWORD=<mqtt-password> \
  -e TZ=Europe/Helsinki \
  ghcr.io/revolutionized-iot2/riot2-node:latest-arm64v8
```

Check it with `docker logs riot2-node`, or read the log files in `/srv/riot2/node/Logs`.

## ESP32 nodes (M5Stack Core2, M5Dial)

These are firmware nodes with a screen:
[RIoT2.Ard.M5Core2.Node](https://github.com/Revolutionized-IoT2/RIoT2.Ard.M5Core2.Node) (touch)
and [RIoT2.Ard.M5Dial.Node](https://github.com/Revolutionized-IoT2/RIoT2.Ard.M5Dial.Node) (rotary
dial).

- Build and flash them with PlatformIO, as described in each repository's README.
- On first boot they open a Wi-Fi setup portal, where you enter Wi-Fi, MQTT and the node id.
- After that they join the bus like any node. Create them in the UI with
  [first-configuration.md](first-configuration.md) and choose their views from the device list.
- They use plain MQTT on 1883, or TLS on 8883 if your broker has a TLS listener. They must be
  able to reach `RIOT2_ORCHESTRATOR_URL`.
- Firmware updates over the air use the reserved command `system.ota`.

## Time-series storage: InfluxDB and Grafana

[RIoT2.Connector.InfluxDB](https://github.com/Revolutionized-IoT2/RIoT2.Connector.InfluxDB) writes
every report (and optionally every command) to InfluxDB 2. Number and boolean values are written
directly; entity values are flattened into one field per leaf. Its README shows how to set up
InfluxDB and the point schema for Grafana queries.

```bash
docker run -d --name riot2-influxdb --restart unless-stopped -p 8083:8080 \
  -e RIOT2_CONNECTOR_ID=<connector-guid> \
  -e RIOT2_MQTT_IP=<broker-host> -e RIOT2_MQTT_USERNAME=<mqtt-user> -e RIOT2_MQTT_PASSWORD=<mqtt-password> \
  -e RIOT2_INFLUXDB_HOST=http://<influx-host>:8086 -e RIOT2_INFLUXDB_TOKEN=<token> \
  -e RIOT2_INFLUXDB_BUCKET=<bucket> -e RIOT2_INFLUXDB_ORGANIZATION=<org> \
  -e RIOT2_HANDLE_COMMANDS=false -e TZ=Europe/Helsinki \
  ghcr.io/revolutionized-iot2/riot2-influxdb:latest
```

If InfluxDB is unreachable, the connector loses those points: there is no spool yet
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

- Run the orchestrator with `--network host` (mDNS and IPv6 discovery), and drop `-p`. The
  container port 8080 is used directly; with host networking, the non-root process can't bind
  ports below 1024.
- Mount `/app/MatterCredentials` (owned by UID 1654). It holds the fabric credentials. Back it
  up, and keep it secret.
- Enable and commission the bridge on the UI's **Matter** page (QR code). Which devices are
  bridged is declared by the device plugins (`matterEndpoints`).

## Operations

| Task | How |
|---|---|
| Health | `GET /health` on orchestrator, node, Elsa and connector (Elsa and connector also `/healthz`). The orchestrator's health includes its MQTT connection. |
| Logs | `docker logs <container>`. Orchestrator and node also write daily files to `/app/Logs`. |
| Back up | Orchestrator `/app/StoredObjects` (all configuration) and `/app/MatterCredentials`, Elsa `/app/Data` (workflows, SQLite), node `/app/Data`. All of them can contain secrets. |
| Update plugins | Replace the files in the node's `Plugins/` and restart. Or set the node's **Plugin package Url**: the node downloads the zip and installs it on its next restart. That install replaces the whole `Plugins/` folder. |
| Update images | Read [upgrading.md](upgrading.md) first. Release and update the Node image and the plugin package together. |
| Time zone | `TZ` on every container (image default `Europe/Helsinki`). |

A single `docker-compose.yml` for the whole stack, metrics and a backup command are planned in
[design 7.4](../design/operations.md).
