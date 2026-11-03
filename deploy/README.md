# deploy

Applies to: installing and running RIoT2 with Docker Compose. Step-by-step guide:
[getting-started.md](../docs/guides/getting-started.md). Variables:
[env-vars.md](../docs/contracts/env-vars.md#compose-install-deploy).

```bash
cp .env.example .env    # set RIOT2_HOST and RIOT2_MQTT_PASSWORD
docker compose up -d --wait
```

| File | Use |
|---|---|
| `docker-compose.yml` | Mosquitto, orchestrator (which runs the workflows) and UI; the node with `--profile node`, and the separate Elsa workflow host with `--profile remote-workflows` and `RIOT2_WORKFLOW_MODE=remote` ([ADR 0016](../docs/adr/0016-integrated-workflows-and-llm.md)) |
| `compose.influx.yml` | Adds InfluxDB, Grafana and the InfluxDB connector ([deployment.md](../docs/guides/deployment.md#time-series-storage-influxdb-and-grafana)) |
| `compose.observability.yml` | Adds the OpenTelemetry Collector, Prometheus and Grafana with the RIoT2 system dashboard ([deployment.md](../docs/guides/deployment.md#metrics-prometheus-and-grafana)) |
| `compose.homeassistant.yml` | Adds the Home Assistant connector ([deployment.md](../docs/guides/deployment.md#home-assistant)) |
| `compose.matter.yml` | Puts the orchestrator on the host network for the Matter bridge ([deployment.md](../docs/guides/deployment.md#matter-apple-home-google-home-amazon-alexa)) |
| `compose.node-raspi.yml` | A node on a Raspberry Pi, run on the Pi itself ([deployment.md](../docs/guides/deployment.md#raspberry-pi-node)) |
| `.env.example` | Every variable the compose files read; copy it to `.env` |
| `backup.sh`, `restore.sh` (`.ps1` for PowerShell) | Back up and restore every volume, InfluxDB, `.env` and `plugins/` ([backup-and-restore.md](../docs/guides/backup-and-restore.md)) |
| `mosquitto/` | Broker configuration, and `start.sh`, which creates the broker account from `.env` |
| `grafana/datasources/` | Grafana's InfluxDB and Prometheus data sources |
| `grafana/dashboards/` | The RIoT2 system dashboard; its metrics are in [metrics.md](../docs/contracts/metrics.md) |
| `otel-collector/`, `prometheus/` | Collector and Prometheus configuration for `compose.observability.yml` |

- Images are pinned to release tags. An upgrade is a new tag here, so read
  [upgrading.md](../docs/guides/upgrading.md) before `git pull`.
- `.env`, `plugins/`, `backups/` and `docker-compose.override.yml` are local to an installation
  and ignored by git.
- [deploy-check.yml](../.github/workflows/deploy-check.yml) validates the files and starts the
  stack on every change here; [nightly-smoke.yml](../.github/workflows/nightly-smoke.yml) starts the
  released stack every night and opens a `nightly-smoke` issue when a health check fails. docs-check fails if `.env.example` and the compose files disagree.
