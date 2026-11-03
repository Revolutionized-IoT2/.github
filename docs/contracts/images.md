# Ports, volumes and images

Applies to: every deployable component. Variables: [env-vars.md](env-vars.md).
Ports and users come from each repository's `Dockerfile`. Image names come from each repository's
`.github/workflows/release.yml` ([guides/ci.md](../guides/ci.md)).

| Component | Image (`ghcr.io/revolutionized-iot2/…`) | Container port(s) | Runs as | Persistent paths |
|---|---|---|---|---|
| Orchestrator | `riot2-orchestrator:latest`, `:<tag>` | 8080 | `$APP_UID` (1654) | `/app/StoredObjects` (configuration, and the outbox `outbox.db`), `/app/Logs`, `/app/MatterCredentials`, `/app/Backups` (1.7.0). Don't mount `/app/Data`: it holds the image's `Manifest.json`. |
| Node | `riot2-node:latest`, `:<tag>`; ARM64: `:latest-arm64v8`, `:<tag>-arm64v8` | 80 | root (no `USER` directive) | `/app/Data`, `/app/Logs`, `/app/Plugins` |
| Elsa | `riot2-elsa:latest`, `:<tag>` | 8080 (web/Studio), 5003 (gRPC) | `app` (1654) | `/app/Data` (`elsa.sqlite.db`), `/app/Logs` (1.4.0) |
| InfluxDB connector | `riot2-influxdb:latest`, `:<tag>` | 8080 | `app` (1654) | `/app/Logs` (1.3.0), `/app/Data` (the spool, 1.9.0) |
| Prometheus exporter | `riot2-prometheus-exporter:latest`, `:<tag>` (1.0.0) | 8080 (`/metrics`) | `app` (1654) | `/app/Logs` |
| Home Assistant connector | `riot2-homeassistant:latest`, `:<tag>` (1.0.0) | 8080 (`/health`) | `app` (1654) | `/app/Logs` |
| UI | `riot2-ui:latest`, `:<tag>` | 8080 (nginx; 80 before 1.1.0) | `nginx` (101) | none |

- No image declares `VOLUME`. Mount the paths above yourself, or use [deploy/](../../deploy/),
  which uses named volumes.
- Every .NET service writes `Logs/RIoT2.log` (`/app/Logs` in the images) in the format of
  `RIOT2_LOG_FORMAT`: a new file every day and at 50 MB, 14 files kept. Without a volume the
  files are lost when the container is recreated; `docker logs` has the same lines.
- Every image has a Docker `HEALTHCHECK` on `GET /health` (the UI: `GET /`). The orchestrator
  has one since 1.3.1, and the node since 1.3.1.
- Host directories bind-mounted into non-root containers must be writable by UID 1654
  (`sudo chown -R 1654:1654 <dir>`). Named volumes get the right owner from the image.
- Matter commissioning needs `--network host` (mDNS, IPv6). With host networking, the non-root
  orchestrator cannot bind ports below 1024, so keep 8080.
- Raspberry Pi nodes that use GPIO, I2C or Bluetooth run with `--privileged` and
  `-v /var/run/dbus:/var/run/dbus:ro`.
- MQTT broker: TCP 1883 for .NET (or `RIOT2_MQTT_PORT`) and firmware, WebSocket 9001 for the UI, and 8883 for firmware
  TLS.
