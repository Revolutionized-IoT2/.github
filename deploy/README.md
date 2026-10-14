# deploy

Applies to: installing and running RIoT2 with Docker Compose. Step-by-step guide:
[getting-started.md](../docs/guides/getting-started.md). Variables:
[env-vars.md](../docs/contracts/env-vars.md#compose-install-deploy).

```bash
cp .env.example .env    # set RIOT2_HOST, RIOT2_MQTT_PASSWORD and ELSA_IDENTITY_SIGNING_KEY
docker compose up -d --wait
```

| File | Use |
|---|---|
| `docker-compose.yml` | Mosquitto, orchestrator, Elsa and UI; the node with `--profile node` |
| `compose.influx.yml` | Adds InfluxDB, Grafana and the InfluxDB connector ([deployment.md](../docs/guides/deployment.md#time-series-storage-influxdb-and-grafana)) |
| `compose.matter.yml` | Puts the orchestrator on the host network for the Matter bridge ([deployment.md](../docs/guides/deployment.md#matter-apple-home-google-home-amazon-alexa)) |
| `compose.node-raspi.yml` | A node on a Raspberry Pi, run on the Pi itself ([deployment.md](../docs/guides/deployment.md#raspberry-pi-node)) |
| `.env.example` | Every variable the compose files read; copy it to `.env` |
| `mosquitto/` | Broker configuration, and `start.sh`, which creates the broker account from `.env` |
| `grafana/datasources/` | Grafana's InfluxDB data source |

- Images are pinned to release tags. An upgrade is a new tag here, so read
  [upgrading.md](../docs/guides/upgrading.md) before `git pull`.
- `.env`, `plugins/` and `docker-compose.override.yml` are local to an installation and ignored
  by git.
- [deploy-check.yml](../.github/workflows/deploy-check.yml) validates the files and starts the
  stack on every change here. docs-check fails if `.env.example` and the compose files disagree.
