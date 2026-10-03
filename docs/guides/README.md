# Guides

Applies to: people installing, running and operating RIoT2. Contract references (variables,
ports, APIs) are in [../contracts/](../contracts/). The design is described in
[../architecture/](../architecture/overview.md).

| Guide | Use it to |
|---|---|
| [getting-started.md](getting-started.md) | Install broker, orchestrator, node, UI and Elsa on one Docker host |
| [first-configuration.md](first-configuration.md) | Configure your first node in the UI, test a webhook, create a variable |
| [deployment.md](deployment.md) | Raspberry Pi and ESP32 nodes, InfluxDB/Grafana, mobile app, Matter, several hosts, operations |
| [security.md](security.md) | Understand the security model, and what to do on an isolated network |
| [upgrading.md](upgrading.md) | Update images safely; breaking changes per release |

Every guide uses placeholders such as `<host>`, `<mqtt-user>` and `<node-guid>`. Never paste
real credentials into documentation.
