# Upgrading deployments

Applies to: operators of orchestrator, node, Elsa, InfluxDB connector and UI containers.
Current values for ports, users and variables: [env-vars.md](../contracts/env-vars.md).

## September 2026 images (breaking deployment changes)

| Image | Change | Action |
|---|---|---|
| orchestrator | Listens on **8080** and runs as non-root UID **1654** | Map `-p 80:8080` (or set `ASPNETCORE_HTTP_PORTS`). `sudo chown -R 1654:1654` the host directories mounted at `/app/StoredObjects`, `/app/Logs` and `/app/MatterCredentials`. With `--network host`, the non-root process can't bind ports below 1024. |
| orchestrator, node, elsa, influxdb | Required environment variables have no defaults; startup fails with a clear log if they are missing or invalid | Set them explicitly (see [env-vars.md](../contracts/env-vars.md)). |
| elsa | Web on **8080**, gRPC still on **5003**, non-root, `ELSA_IDENTITY_SIGNING_KEY` required in Production | Generate a key with `openssl rand -base64 48`, `chown` `/app/Data`, and point `RIOT2_WORKFLOW_URL` at the mapped web port. |
| influxdb | Listens on **8080**, non-root | Update the port mapping. |
| ui | No default MQTT values. Env values are rendered again on every container start (previously only on the first start). | Set the `VITE_MQTT_*` variables. |
| node | Still port 80 and root (GPIO, D-Bus and serial need privileges) | Only the environment variable requirement changes. |

Health endpoints: orchestrator/node/elsa/influx expose `GET /health` (elsa and influx also keep
`/healthz`). The UI image has a `wget` health check on `/`.
