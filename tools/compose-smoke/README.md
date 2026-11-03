# Compose smoke test

Applies to: `.github/deploy` and the two workflows that start it on a runner,
[deploy-check.yml](../../.github/workflows/deploy-check.yml) (every change in `deploy/`) and
[nightly-smoke.yml](../../.github/workflows/nightly-smoke.yml) (every night, the released stack with every
optional file; [design 7.4](../../docs/design/operations.md) phase 5, [I40](../../docs/increments/phase-3-4.md#i40-nightly-compose-smoke-test-s)).

| File | What it does |
|---|---|
| `env.sh` | Creates `deploy/.env` from `.env.example` for a clean runner: `RIOT2_HOST`, random secrets, and with `--observability` the OTLP endpoint. |
| `health.py` | Polls the running stack until every check passes or the deadline (default 120 s after `--since`) passes, then prints a Markdown table (also to the job summary) and exits 1 if a check failed. |
| `test_health.py` | Self-test of `health.py`; the hub's CI runs it. |

`health.py` checks, depending on `--files` and `--profiles`:

- every container is running, and every one with a health check is healthy (`docker compose ps`);
- `GET /health` of the orchestrator (8080), with the `node` profile the node (8081), and with the
  `remote-workflows` profile Elsa (8082); the UI (`/` on 80) and its `/api` proxy;
- the orchestrator's workflow engine (`GET /api/workflows/status`): available, and `remote` with the
  `remote-workflows` profile, `embedded` without it;
- with `compose.influx.yml`: InfluxDB's `/health` and the InfluxDB connector's own health through the
  orchestrator's `GET /api/v2/connectors`;
- with `compose.observability.yml`: Prometheus `/-/ready`, the Prometheus exporter's health the same way,
  and `up{job="riot2-values"}` (Prometheus scrapes the exporter);
- with either: Grafana's `/api/health`.

To run it by hand on a Docker host, in `deploy/`:

```bash
started=$(date +%s)
docker compose -f docker-compose.yml -f compose.influx.yml up -d
python3 ../tools/compose-smoke/health.py --host "$(hostname -I | awk '{print $1}')" \
  --files docker-compose.yml,compose.influx.yml --since "$started"
```

Self-test: `python tools/compose-smoke/test_health.py`.
