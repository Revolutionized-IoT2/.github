# 0009. Connector SDK, with Influx as the reference connector (A6)

- Status: Accepted
- Date: 2026-10-12
- Applies to: RIoT2.Core (new `RIoT2.Connector.Sdk` package), RIoT2.Connector.InfluxDB, future
  connectors, Orchestrator, UI

## Context

`RIoT2.Connector.InfluxDB` is the only connector, and about three quarters of its code is generic
(configuration, MQTT lifecycle, template catalog, queue). It loses data when InfluxDB is down. See
proposal [A6](../architecture/target.md#a6-build-a-connector-sdk) and
[design 7.3](../design/connector-sdk.md).

## Decision

- `RIoT2.Connector.Sdk` is a package in the RIoT2.Core repository, released from the same tag.
  It provides configuration validation, the MQTT lifecycle, the orchestrator handshake, the
  template catalog, a bounded queue with an optional disk spool, batching, retry, dead letters,
  health and metrics.
- A connector implements only `IConnectorSink`. The SDK queues and spools raw `ConnectorMessage`
  envelopes; the sink maps them at write time.
- Connectors identify as `NodeType.Connector = 4` (additive).
- Connectors that write back into RIoT2 must use `POST /api/v2/commands` through
  `IRiot2CommandClient`. They must never publish command topics directly.
- Influx is migrated first and becomes the reference connector.

## Consequences

- New connectors (Prometheus, Home Assistant, Timescale) are small. Scheduled in roadmap phase 3.
- The Influx spool is on by default, so outages no longer leave permanent gaps in history.

## Alternatives considered

A shared base class copied into each connector repository: rejected, because fixes would have to
be copied too.
