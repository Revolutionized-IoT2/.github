# Guides

Applies to: people installing, running and operating RIoT2. Contract references (variables,
ports, APIs) are in [../contracts/](../contracts/). The design is described in
[../architecture/](../architecture/overview.md).

| Guide | Use it to |
|---|---|
| [getting-started.md](getting-started.md) | Install broker, orchestrator, Elsa, UI and a node on one Docker host with Docker Compose |
| [first-configuration.md](first-configuration.md) | Configure your first node in the UI, test a webhook, create a variable |
| [deployment.md](deployment.md) | Raspberry Pi and ESP32 nodes, InfluxDB/Grafana, metrics, mobile app, Matter, several hosts, operations |
| [security.md](security.md) | Understand the security model, and what to do on an isolated network |
| [backup-and-restore.md](backup-and-restore.md) | Back up and restore the configuration (UI, API, schedule) or the whole install (host scripts) |
| [upgrading.md](upgrading.md) | Update images safely; breaking changes per release ([upgrading-older.md](upgrading-older.md) before 1.3.1) |

Every guide uses placeholders such as `<host>`, `<mqtt-user>` and `<node-guid>`. Never paste
real credentials into documentation.
