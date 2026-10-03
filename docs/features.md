# Feature ideas

Applies to: the whole platform. Unscheduled ideas from the September 2026 review; scheduling is in
[ROADMAP.md](../ROADMAP.md) (phase 4). Promote an idea to an issue or design before building it.

## Platform and UX

- Optional (with [A1](architecture/target.md#a1-optional-security-mode)): user accounts and roles, API tokens, and per-user dashboards.
- An audit log of configuration changes. Useful even for one user, to see what changed and to
  roll back.
- A system health page: node online/offline history, MQTT and API state, workflow delivery queue,
  last error per device, plus a connection status banner in the UI.
- Dashboard import/export and a preview mode. Replace `window.confirm` with an unsaved-changes
  dialog.
- Backup and restore of all orchestrator state from the UI.
- Device capability discovery, so the UI builds forms from plugin-declared schemas.
- Scenes as first-class objects (currently only on firmware), usable from UI, Mobile, Matter and
  Elsa.
- Presence and geofencing from Mobile, plus actionable push notifications that execute commands.
- Mobile on iOS/MacCatalyst, and native (non-WebView) widgets for favourite devices.

## Automation (Elsa activities)

- Debounce/window, threshold/hysteresis, schedule/sun-based (sunrise and sunset) triggers,
  wait-for-state, command-with-timeout/ack, and notification/webhook output.
- Workflow templates for common scenarios such as a motion light or a price-based heater.

## Integrations

- Connectors: Home Assistant MQTT discovery (bidirectional), Prometheus exporter, OpenTelemetry,
  PostgreSQL/Timescale, Azure IoT Hub/Event Hubs, Grafana annotations.
- Devices: Zigbee (zigbee2mqtt bridge), Shelly, Tasmota, Modbus TCP/RTU, ESPHome native API,
  camera snapshots with local image classification.
- Matter: Door Lock, Window Covering, Fan Control, Thermostat, Electrical Energy/Power Measurement,
  Air Quality, Valve, Mode Select and Switch device types. Also BLE/NFC/UDC commissioning, OTA
  Provider, and Matter controller mode to pull third-party Matter devices into RIoT2.

## Firmware

- Integrate `WiegandI2C` as a peripheral: I2C `0x26`, 3-byte UID, published as a string report,
  with an optional IRQ pin.
- QR-code provisioning, diagnostics export, and an OTA channel with staged rollout. Optional with
  A1: a per-device AP password, TLS certificate enrollment and signed OTA.
