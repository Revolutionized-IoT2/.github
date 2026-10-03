# Revolutionized-IoT2

RIoT2 is a generic, self-hosted platform for running Internet of Things scenarios, from a smart
home to a lab full of sensors. Devices talk over MQTT, a central orchestrator owns configuration
and state, [Elsa 3](https://docs.elsaworkflows.io/) workflows provide automation, and a web UI,
a mobile app, [Matter](https://csa-iot.org/all-solutions/matter/) controllers (Apple Home, Google
Home, Amazon Alexa) and Grafana show and control it all.

## How it works

- **Nodes** connect to the MQTT bus and host **devices**: sensors, actuators and integrations,
  loaded as plugins. A node runs as a Docker container (also on a Raspberry Pi) or as firmware on
  ESP32 devices with a screen.
- Devices publish **reports** (for example "temperature is 21.5") and receive **commands** (for
  example "turn the lamp on").
- The **orchestrator** is the hub. It stores every node's configuration, tracks state and
  history, routes commands, and forwards reports to Elsa for automation.
- **Connectors** bridge the bus to external systems, such as InfluxDB for Grafana dashboards.
- RIoT2 is designed for an isolated, single-user network: it is simple to run, and it has no
  login. See [security](https://github.com/Revolutionized-IoT2/.github/blob/main/docs/guides/security.md).

More detail: [architecture overview](https://github.com/Revolutionized-IoT2/.github/blob/main/docs/architecture/overview.md).

## Get started

1. [Getting started](https://github.com/Revolutionized-IoT2/.github/blob/main/docs/guides/getting-started.md): broker, orchestrator, node, UI and Elsa
   on one Docker host.
2. [Configure your first node](https://github.com/Revolutionized-IoT2/.github/blob/main/docs/guides/first-configuration.md): a guided tour of the UI.
3. [Deployment variations](https://github.com/Revolutionized-IoT2/.github/blob/main/docs/guides/deployment.md): Raspberry Pi and ESP32 nodes,
   InfluxDB/Grafana, the mobile app and Matter.

Already running RIoT2? Read [upgrading](https://github.com/Revolutionized-IoT2/.github/blob/main/docs/guides/upgrading.md) before you pull new images. When you update a node, update the node image before you install the new plugin zip.

## Repositories

| Repository | Description |
|---|---|
| [RIoT2.Core](https://github.com/Revolutionized-IoT2/RIoT2.Core) | Shared library with the common data model, MQTT conventions, and services used by every other component. |
| [RIoT2.Net.Orchestrator](https://github.com/Revolutionized-IoT2/RIoT2.Net.Orchestrator) | The central hub: tracks nodes, forwards reports to Elsa, and coordinates the system over MQTT. |
| [RIoT2.Net.Node](https://github.com/Revolutionized-IoT2/RIoT2.Net.Node) | The agent that runs on IoT hardware/hubs and dynamically loads device plugins. |
| [RIoT2.Net.Devices](https://github.com/Revolutionized-IoT2/RIoT2.Net.Devices) | The default device plugin catalog for the Node (webhooks, MQTT, Netatmo, Philips Hue, Firebase messaging, electricity price, and more). |
| [RIoT2.Net.RasPi.Devices](https://github.com/Revolutionized-IoT2/RIoT2.Net.RasPi.Devices) | A device plugin catalog for Raspberry Pi hardware, covering GPIO, I2C, Bluetooth, serial, and Z-Wave devices. |
| [RIoT2.Ard.M5Core2.Node](https://github.com/Revolutionized-IoT2/RIoT2.Ard.M5Core2.Node) | ESP32 firmware turning an M5Stack Core2 into a touchscreen RIoT2 node (lights, scenes, sensors). |
| [RIoT2.Ard.M5Dial.Node](https://github.com/Revolutionized-IoT2/RIoT2.Ard.M5Dial.Node) | ESP32 firmware turning an M5Stack M5Dial into a rotary-dial RIoT2 node. |
| [RIoT2.Ard.Shared](https://github.com/Revolutionized-IoT2/RIoT2.Ard.Shared) | Shared Wi-Fi/MQTT/provisioning/OTA firmware library used by both M5 node firmwares. |
| [RIoT2.Ard.WiegandI2C](https://github.com/Revolutionized-IoT2/RIoT2.Ard.WiegandI2C) | An ATtiny85 sketch that decodes Wiegand RFID/badge readers and exposes the code over I2C. |
| [RIoT2.UI](https://github.com/Revolutionized-IoT2/RIoT2.UI) | The web dashboard for monitoring devices, configuring nodes, and opening Elsa Studio. |
| [RIoT2.Mobile](https://github.com/Revolutionized-IoT2/RIoT2.Mobile) | A .NET MAUI mobile app that displays the dashboard and receives Firebase push notifications. |
| [RIoT2.Matter](https://github.com/Revolutionized-IoT2/RIoT2.Matter) | A managed .NET implementation of the Matter smart-home protocol, for interop with controllers like Apple Home and Google Home. |
| [RIoT2.Elsa](https://github.com/Revolutionized-IoT2/RIoT2.Elsa) | Elsa 3 workflow engine and Studio, providing automation for RIoT2. |
| [RIoT2.Connector.InfluxDB](https://github.com/Revolutionized-IoT2/RIoT2.Connector.InfluxDB) | Bridges the MQTT bus into InfluxDB for Grafana visualization. |
| [RIoT2.Tests](https://github.com/Revolutionized-IoT2/RIoT2.Tests) | Unit and reliability test suite for RIoT2.Core, the Orchestrator and the InfluxDB connector. |

## Documentation

| Looking for | Go to |
|---|---|
| Guides (install, configure, operate) | [docs/guides](https://github.com/Revolutionized-IoT2/.github/blob/main/docs/guides/README.md) |
| Architecture and design decisions | [overview](https://github.com/Revolutionized-IoT2/.github/blob/main/docs/architecture/overview.md), [ADRs](https://github.com/Revolutionized-IoT2/.github/blob/main/docs/adr/README.md) |
| MQTT, HTTP/gRPC, variables, configuration format | [docs/contracts](https://github.com/Revolutionized-IoT2/.github/blob/main/docs/contracts/) |
| What's planned | [Roadmap](https://github.com/Revolutionized-IoT2/.github/blob/main/ROADMAP.md), [backlog](https://github.com/Revolutionized-IoT2/.github/blob/main/docs/backlog/README.md), [target architecture](https://github.com/Revolutionized-IoT2/.github/blob/main/docs/architecture/target.md) |
| Everything | [Documentation index](https://github.com/Revolutionized-IoT2/.github/blob/main/docs/README.md) |

## Contributing

- Each repository has a README.md for people and an AGENTS.md for AI coding agents.
- The workspace-wide guide for agents is [AGENTS.md](https://github.com/Revolutionized-IoT2/.github/blob/main/AGENTS.md).
- Platform contracts change additively, and they are documented in
  [docs/contracts](https://github.com/Revolutionized-IoT2/.github/blob/main/docs/contracts/) in the same change.
