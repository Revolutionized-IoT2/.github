# Getting started

Applies to: a first installation of RIoT2 on one Docker host in an isolated home or lab network,
with the compose files in [deploy/](../../deploy/). For variations (Raspberry Pi node, ESP32
nodes, InfluxDB, Matter, several hosts), see [deployment.md](deployment.md). The reference for
every variable is [env-vars.md](../contracts/env-vars.md).

One `docker compose up` starts the whole stack:

| Service | What it is | Host port(s) |
|---|---|---|
| `mosquitto` | MQTT broker (Eclipse Mosquitto) | 1883 (MQTT), 9001 (WebSocket for the UI) |
| `orchestrator` | Configuration, state and command routing | 8080 |
| `elsa` | Workflows: Elsa Studio and the gRPC trigger endpoint | 8082 (Studio), 5003 (gRPC) |
| `ui` | Web dashboard | 80 |
| `node` | A node with device plugins, under the `node` profile | 8081 |

Compose starts them in order: the broker, then the orchestrator once the broker is healthy, then
the others once the orchestrator is healthy. Data lives in named Docker volumes.

## Before you start

- Install Docker Engine with the Compose plugin (`docker compose version` shows 2.24 or later).
- Pick the host's LAN IP or DNS name. Browsers, nodes and ESP32 firmware connect to it, so it
  can't be `localhost`.
- Keep the network isolated. RIoT2 has no login by design ([security.md](security.md)).

## 1. Get the files and fill in .env

```bash
git clone --depth 1 https://github.com/Revolutionized-IoT2/.github.git riot2
cd riot2/deploy
cp .env.example .env
```

Edit `.env` and fill in the required values at the top:

| Variable | Value |
|---|---|
| `RIOT2_HOST` | The host's LAN address, for example `192.168.1.20`. |
| `RIOT2_MQTT_PASSWORD` | A password for the broker account `riot2`. The broker creates the account on every start. |
| `ELSA_IDENTITY_SIGNING_KEY` | Output of `openssl rand -base64 48`. |

The rest has working defaults: ids, host ports and the time zone (`TZ`, default
`Europe/Helsinki`). `.env` holds passwords, so keep it private; `deploy/.gitignore` keeps it out
of git.

## 2. Start the stack

```bash
docker compose up -d --wait
```

`--wait` returns when every service reports healthy. Then:

- `docker compose ps` shows each service as `healthy`.
- `curl http://<host>:8080/health` returns `Healthy`. If a service doesn't start,
  `docker compose logs <service>` names the missing or invalid variable.
- Open `http://<host>/`. The UI shows "Connecting..." until the orchestrator answers. If it stays
  there, check that port 9001 is reachable from the browser, and reload the page.

## 3. Add the node

The node hosts devices, which are loaded from plugins. Download the default device plugins,
`RIoT2.Net.Devices_<version>.zip`, from the
[RIoT2.Net.Devices releases](https://github.com/Revolutionized-IoT2/RIoT2.Net.Devices/releases),
unzip them into `deploy/plugins`, and start the node:

```bash
unzip RIoT2.Net.Devices_<version>.zip -d plugins
docker compose --profile node up -d --wait
```

- `docker compose logs node` should show `Found N devices from plugins`. Without plugins, the node
  logs `NO PLUGINS LOADED` and keeps running without devices.
- Plugins load only at start: run `docker compose restart node` after changing `plugins/`.
- Use the plugin release that matches the node image. Plugins run inside the node's
  `RIoT2.Core` version.
- Add `--profile node` to every later `docker compose` command, or set `COMPOSE_PROFILES=node` in
  `.env`.

## 4. Elsa (workflows)

Elsa starts with the stack, and the orchestrator delivers reports to it over gRPC.

- The UI's **Rules** menu entry opens Elsa Studio at `http://<host>:8082`.
- Studio uses Elsa's built-in admin account (`admin` / `password`). It is not suitable outside an
  isolated network (backlog S7).
- Workflows use the RIoT2 activities `RIoTTrigger` (start on a report), `RIoTData` (read report,
  command or variable values) and `RIoTOutput` (send a command or set a variable). For workflow
  authoring in general, see the [Elsa 3 documentation](https://docs.elsaworkflows.io/).
- Without Elsa (`docker compose stop elsa`), the system still tracks state, but no automation
  runs; triggers wait in the orchestrator's outbox until they expire.

## 5. Configure your first node

Continue with [first-configuration.md](first-configuration.md): create the node in the UI, add a
webhook device, test it, and create a variable.

## Day-to-day commands

Run them in `deploy/`:

| Task | Command |
|---|---|
| Status | `docker compose ps` |
| Logs | `docker compose logs -f orchestrator` |
| Stop, keeping data | `docker compose down` |
| Upgrade | Update the files (`git pull`), read [upgrading.md](upgrading.md), then `docker compose up -d --wait` |
| Remove everything, data included | `docker compose down --volumes` |

The volumes `riot2_orchestrator-storedobjects` (all configuration), `riot2_orchestrator-matter`
(Matter credentials) and `riot2_elsa-data` (workflows) hold what to back up. All can contain
secrets.

## Next

- Add hardware nodes, InfluxDB/Grafana, the mobile app or Matter: [deployment.md](deployment.md).
- Understand the moving parts: [architecture overview](../architecture/overview.md).
- Keep it safe: [security.md](security.md). Update images: [upgrading.md](upgrading.md).
