# Getting started

Applies to: a first installation of RIoT2 on one Docker host in an isolated home or lab network,
with the compose files in [deploy/](../../deploy/). For variations (Raspberry Pi node, ESP32
nodes, InfluxDB, Matter, several hosts), see [deployment.md](deployment.md). The reference for
every variable is [env-vars.md](../contracts/env-vars.md).

One `docker compose up` starts the whole stack:

| Service | What it is | Host port(s) |
|---|---|---|
| `mosquitto` | MQTT broker (Eclipse Mosquitto) | 1883 (MQTT), 9001 (WebSocket for the UI) |
| `orchestrator` | Configuration, state, command routing, and the workflows (Elsa, embedded) | 8080 |
| `ui` | Web dashboard and workflow designer; it proxies `/api` to the orchestrator | 80 |
| `node` | A node with device plugins, under the `node` profile | 8081 |
| `elsa` | The separate workflow host, only under the `remote-workflows` profile ([ADR 0016](../adr/0016-integrated-workflows-and-llm.md)) | 8082, 5003 (gRPC) |

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

## 4. Workflows

Workflows run in the orchestrator (Elsa 3, embedded), which hands every report to them through its
outbox. Build them on the UI's **Workflows** page.

- Drag activities from the palette onto the canvas, connect their outcomes, and set their inputs in
  the inspector. **Publish** makes the triggers live; **Runs** shows what ran and why it stopped.
- Workflows use the RIoT2 activities `RIoTTrigger` (start on a report), `RIoTData` (read report,
  command or variable values), `RIoTOutput` (send a command or set a variable), "RIoT Command
  with confirmation" (send a command and wait until the device ran it) and *Run LLM* (ask a
  language model, set up on the **AI models** page). The [automation guide](automation.md) has the
  rest, and the [Elsa 3 documentation](https://docs.elsaworkflows.io/) covers workflows in general.
- To run them in the separate Elsa container instead, set `RIOT2_WORKFLOW_MODE=remote` in `.env`
  and add `--profile remote-workflows`. Without a running engine the system still tracks state,
  and triggers wait in the outbox until they expire.

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
| Back up everything | `./backup.sh --profile node` (`backups/`; restore with `./restore.sh`) |
| Upgrade | Update the files (`git pull`), read [upgrading.md](upgrading.md), then `docker compose up -d --wait` |
| Remove everything, data included | `docker compose down --volumes` |

The orchestrator also backs up its configuration every night (UI: **Backup**). Both kinds of
backup, and how to restore them: [backup-and-restore.md](backup-and-restore.md). Backups contain
secrets.

## Next

- Add hardware nodes, InfluxDB/Grafana, the mobile app or Matter: [deployment.md](deployment.md).
- Understand the moving parts: [architecture overview](../architecture/overview.md).
- Keep it safe: [security.md](security.md). Update images: [upgrading.md](upgrading.md).
