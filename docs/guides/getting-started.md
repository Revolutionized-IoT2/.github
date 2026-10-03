# Getting started

Applies to: a first installation of RIoT2 on one Docker host in an isolated home or lab network.
For variations (Raspberry Pi node, ESP32 nodes, InfluxDB, Matter, several hosts), see
[deployment.md](deployment.md). The reference for every variable is
[env-vars.md](../contracts/env-vars.md).

You will run five containers and then configure your first node in the UI:

| Step | Component | Host port(s) used in this guide |
|---|---|---|
| 1 | MQTT broker (Eclipse Mosquitto) | 1883 (MQTT), 9001 (WebSocket for the UI) |
| 2 | Orchestrator | 8080 |
| 3 | Node with the default device plugins | 8081 |
| 4 | UI | 80 |
| 5 | Elsa (workflows) | 8082 (Studio), 5003 (gRPC) |
| 6 | [Configure your first node](first-configuration.md) | — |

Before you start:

- Install Docker on the host, and pick the host's LAN IP. This guide calls it `<host>`.
- Generate one GUID for each of the orchestrator, the node and Elsa. On Linux use `uuidgen`; in
  PowerShell use `[guid]::NewGuid()`. Every RIoT2 participant needs its own id.
- Keep the network isolated. RIoT2 has no login by design
  ([security.md](security.md)).
- Host directories under `/srv/riot2` hold persistent data. Containers that run as non-root
  (orchestrator, Elsa) need their directories owned by UID 1654.

## 1. MQTT broker

Create `/srv/riot2/mosquitto/config/mosquitto.conf`:

```
persistence true
persistence_location /mosquitto/data/
allow_anonymous false
password_file /mosquitto/config/password.txt

listener 1883
listener 9001
protocol websockets
```

The WebSocket listener on 9001 is required: the UI's browser code connects to it directly.

Create a user, then start the broker:

```bash
docker run --rm -v /srv/riot2/mosquitto/config:/mosquitto/config eclipse-mosquitto:2 \
  mosquitto_passwd -b -c /mosquitto/config/password.txt <mqtt-user> <mqtt-password>

docker run -d --name mosquitto --restart unless-stopped -p 1883:1883 -p 9001:9001 \
  -v /srv/riot2/mosquitto/config:/mosquitto/config \
  -v /srv/riot2/mosquitto/data:/mosquitto/data \
  eclipse-mosquitto:2
```

## 2. Orchestrator

```bash
sudo mkdir -p /srv/riot2/orchestrator/StoredObjects /srv/riot2/orchestrator/Logs
sudo chown -R 1654:1654 /srv/riot2/orchestrator

docker run -d --name riot2-orchestrator --restart unless-stopped -p 8080:8080 \
  -v /srv/riot2/orchestrator/StoredObjects:/app/StoredObjects \
  -v /srv/riot2/orchestrator/Logs:/app/Logs \
  -e RIOT2_ORCHESTRATOR_ID=<orchestrator-guid> \
  -e RIOT2_ORCHESTRATOR_URL=http://<host>:8080 \
  -e RIOT2_MQTT_IP=<host> -e RIOT2_MQTT_USERNAME=<mqtt-user> -e RIOT2_MQTT_PASSWORD=<mqtt-password> \
  -e TZ=Europe/Helsinki \
  ghcr.io/revolutionized-iot2/riot2-orchestrator:latest
```

- `RIOT2_ORCHESTRATOR_URL` is sent to every node, which uses it to download its configuration. It
  must be reachable from the nodes, so don't use `localhost`.
- `/app/StoredObjects` holds all configuration: nodes, dashboard and variables. Back it up.
- Check: `curl http://<host>:8080/health` returns `Healthy`. If the container exits right away,
  `docker logs riot2-orchestrator` names the missing or invalid variable.

## 3. Node

Download the default device plugins: `RIoT2.Net.Devices_<version>.zip` from the
[RIoT2.Net.Devices releases](https://github.com/Revolutionized-IoT2/RIoT2.Net.Devices/releases).
Unzip it into the plugins directory:

```bash
sudo mkdir -p /srv/riot2/node/Data /srv/riot2/node/Logs /srv/riot2/node/Plugins
sudo unzip RIoT2.Net.Devices_<version>.zip -d /srv/riot2/node/Plugins

docker run -d --name riot2-node --restart unless-stopped -p 8081:80 \
  -v /srv/riot2/node/Data:/app/Data \
  -v /srv/riot2/node/Logs:/app/Logs \
  -v /srv/riot2/node/Plugins:/app/Plugins \
  -e RIOT2_NODE_ID=<node-guid> \
  -e RIOT2_NODE_URL=http://<host>:8081 \
  -e RIOT2_MQTT_IP=<host> -e RIOT2_MQTT_USERNAME=<mqtt-user> -e RIOT2_MQTT_PASSWORD=<mqtt-password> \
  -e TZ=Europe/Helsinki \
  ghcr.io/revolutionized-iot2/riot2-node:latest
```

- Plugins load only at container start. Restart the node after changing `Plugins/`.
- `docker logs riot2-node` should show `Found N devices from plugins`. If no plugins are found,
  the node logs `NO PLUGINS LOADED` and keeps running without devices.
- Use the plugin release that matches the node image. Plugins run inside the node's
  `RIoT2.Core` version.

## 4. UI

```bash
docker run -d --name riot2-ui --restart unless-stopped -p 80:80 \
  -e VITE_MQTT_SERVER=<host> -e VITE_MQTT_USER=<mqtt-user> -e VITE_MQTT_PASSWORD=<mqtt-password> \
  -e TZ=Europe/Helsinki \
  ghcr.io/revolutionized-iot2/riot2-ui:latest
```

- The browser connects to `ws://<host>:9001/` with these credentials, so anyone who can open the
  UI can read them ([security.md](security.md)).
- The values are written into the served JavaScript at every container start, so changing them
  only needs a restart.
- Open `http://<host>/`. The UI shows "Connecting..." until the orchestrator answers. If it stays
  there, check the broker's WebSocket listener and reload the page.

## 5. Elsa (workflows)

```bash
sudo mkdir -p /srv/riot2/elsa/Data && sudo chown -R 1654:1654 /srv/riot2/elsa

docker run -d --name riot2-elsa --restart unless-stopped -p 8082:8080 -p 5003:5003 \
  -v /srv/riot2/elsa/Data:/app/Data \
  -e RIOT2_WORKFLOW_ID=<elsa-guid> \
  -e RIOT2_WORKFLOW_URL=http://<host>:8082 \
  -e RIOT2_WORKFLOW_GRPC_URL=http://<host>:5003 \
  -e RIOT2_MQTT_IP=<host> -e RIOT2_MQTT_USERNAME=<mqtt-user> -e RIOT2_MQTT_PASSWORD=<mqtt-password> \
  -e ELSA_IDENTITY_SIGNING_KEY="$(openssl rand -base64 48)" \
  -e TZ=Europe/Helsinki \
  ghcr.io/revolutionized-iot2/riot2-elsa:latest
```

- The orchestrator delivers every report to Elsa over gRPC (`RIOT2_WORKFLOW_GRPC_URL`), so that
  URL must include the published port.
- Once Elsa is online, the UI's **Rules** menu entry opens Elsa Studio at `RIOT2_WORKFLOW_URL`.
- Studio uses Elsa's built-in admin account (`admin` / `password`). It is not suitable outside an
  isolated network (backlog S7).
- Without Elsa, the system still tracks state, but no automation runs.
- Workflows use the RIoT2 activities `RIoTTrigger` (start on a report), `RIoTData` (read report,
  command or variable values) and `RIoTOutput` (send a command or set a variable). For workflow
  authoring in general, see the [Elsa 3 documentation](https://docs.elsaworkflows.io/).

## 6. Configure your first node

Continue with [first-configuration.md](first-configuration.md): create the node in the UI, add a
webhook device, test it, and create a variable.

## Next

- Add hardware nodes, InfluxDB/Grafana, the mobile app or Matter: [deployment.md](deployment.md).
- Understand the moving parts: [architecture overview](../architecture/overview.md).
- Keep it safe: [security.md](security.md). Update images: [upgrading.md](upgrading.md).
