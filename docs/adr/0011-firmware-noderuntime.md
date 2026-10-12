# 0011. Shared firmware NodeRuntime in RIoT2.Ard.Shared (A8)

- Status: Accepted
- Date: 2026-10-12
- Applies to: RIoT2.Ard.Shared, RIoT2.Ard.M5Core2.Node, RIoT2.Ard.M5Dial.Node,
  RIoT2.Ard.WiegandI2C

## Context

The Core2 and Dial firmwares each contain their own Wi-Fi, MQTT, configuration and OTA lifecycle,
mixed with UI code. Fixes have to be made twice. See proposal
[A8](../architecture/target.md#a8-share-a-firmware-noderuntime) and plan
[M5](../plans/m05-firmware-node-runtime.md).

## Decision

- Wi-Fi, MQTT, configuration, OTA and peripheral lifecycle move into a `NodeRuntime` in
  `RIoT2.Ard.Shared`. Board repositories keep only board setup and rendering.
- A shared view-model layer feeds board-specific renderers for Core2 and Dial.
- New peripherals implement the existing `IPeripheral` interface and are registered with
  `PeripheralManager`. `WiegandI2CPeripheral` is the next one.
- Reusable firmware logic must go into `RIoT2.Ard.Shared`, and both board firmwares must build
  after every change to it.

## Consequences

- One fix covers both boards, and a new board needs only setup and renderers.
- Scheduled in roadmap phase 2 (M5), with the Wiegand peripheral in phase 3.

## Alternatives considered

Keeping per-board code and sharing only utilities: rejected, because the lifecycle code is where
the duplicated bugs were found.
