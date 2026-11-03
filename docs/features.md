# Feature ideas

Applies to: the whole platform. Unscheduled ideas from the September 2026 review; scheduling is in
[ROADMAP.md](../ROADMAP.md) (phase 4). Promote an idea to an issue or design before building it.

## Platform and UX

- Optional (with [A1](architecture/target.md#a1-optional-security-mode)): user accounts and roles, API tokens, and per-user dashboards.
- An audit log of configuration changes. Useful even for one user, to see what changed and to
  roll back.
- The system health page and the connection banner are done ([I46](increments/phase-3-4.md#i46-system-health-page-m)). Still open: a persisted
  presence history (today it starts at the orchestrator's start) and alerts when a node goes offline.
- Dashboard import/export and a preview mode. Replace `window.confirm` with an unsaved-changes
  dialog.
- Backup and restore from the UI is done (I21, [backup-and-restore.md](guides/backup-and-restore.md)). Still open:
  restoring single objects (one node or the dashboard) from a backup, and copying backups off the
  host (a NAS share, S3 or WebDAV) on a schedule.
- Device capability discovery, so the UI builds forms from plugin-declared schemas.
- Scenes as first-class objects (currently only on firmware), usable from UI, Mobile, Matter and
  Elsa.
- Presence and geofencing from Mobile, plus actionable push notifications that execute commands.
- Mobile on iOS/MacCatalyst, and native (non-WebView) widgets for favourite devices.

## Automation (Elsa activities)

- Done ([I48](increments/phase-3-4.md#i48-elsa-activity-pack-m), [automation guide](guides/automation.md)):
  debounce and throttle, threshold with hysteresis, schedule and sunrise/sunset triggers,
  wait-for-state, command with confirmation, notification and webhook output, and the motion
  light and price-based heater templates.
- Still open: persisting the debounce, throttle and threshold state across restarts; more
  templates (presence, alarms); a calendar or holiday condition for schedules.

## Integrations

- Connectors: OpenTelemetry, PostgreSQL/Timescale, Azure IoT Hub/Event Hubs, Grafana annotations.
  Done: the Prometheus exporter (I39, `RIoT2.Connector.Prometheus`) and Home Assistant MQTT
  discovery in both directions (I47, `RIoT2.Connector.HomeAssistant`).
- Devices: Zigbee (zigbee2mqtt bridge), Shelly, Tasmota, Modbus TCP/RTU, ESPHome native API,
  camera snapshots with local image classification.
- Matter: Door Lock, Window Covering, Fan Control, Thermostat, Electrical Energy/Power Measurement,
  Air Quality, Valve, Mode Select and Switch device types. Also BLE/NFC/UDC commissioning, OTA
  Provider, and Matter controller mode to pull third-party Matter devices into RIoT2.

## Firmware

- The `WiegandI2C` peripheral is done (I42, `WiegandI2CPeripheral`, M5Core2 and M5Dial 0.6.0).
- QR-code provisioning, diagnostics export, and an OTA channel with staged rollout. Optional with
  A1: a per-device AP password, TLS certificate enrollment and signed OTA.
