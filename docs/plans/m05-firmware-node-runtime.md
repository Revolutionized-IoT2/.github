# M5. Shared firmware view logic and node runtime

Applies to: see the problem description. Status: snapshot from the September 2026 platform review. Verify against the code before starting work.
Index and dependencies: [plans/README.md](README.md). Backlog: [open-issues.md](../backlog/open-issues.md).

**Problem.** Core2 (LVGL, touch) and Dial (M5Canvas, rotary encoder) each implement the same
twelve views: Alert, BLE, Button, Clock, ColorScheme, Notification, Percentage, SceneSelector,
Slider, Timer, Toggle and Value. The rendering differs, but the logic around it is the same:

- pairing report and command templates by `address` into slots,
- parsing command values (`is<bool>()` or `as<int>() != 0`),
- building the `Report` to publish,
- the `build*ViewTemplate()` default configurations, which differ only in `classFullName`.

Both `main.cpp` files (474 and 632 lines) repeat the Wi-Fi, provisioning, MQTT, configuration fetch,
OTA and `system.ota` wiring. `RIoT2.Ard.Shared` already provides the building blocks
(`MqttConnection`, `OrchestratorClient`, `OtaUpdater`, `ProvisioningPortal`, `PeripheralManager`,
`IPeripheral`) but no runtime that ties them together.

## Steps

1. **Shared view models.** Add `riot2/views/` to `RIoT2.Ard.Shared` with one view-model class per
   view type, for example `ToggleModel`, `SliderModel` and `TimerModel`. Each holds the slot state,
   `begin(const DeviceConfiguration&)`, `onCommand(const Command&)` returning "state changed", and
   `makeReport(...)`, plus a `buildTemplate(const char* classPrefix)` for the default configuration.
   These have no display dependencies, so they can be unit-tested in the existing native test
   harness under `RIoT2.Ard.Shared/tests`.
2. **Board views become renderers.** Change the Core2 and Dial views to thin renderers that own a
   model and draw it. Migrate one view type at a time, starting with Toggle, Slider and Value, and
   run `pio run` for both boards after each.
3. **Shared `NodeRuntime`.** Add `riot2::NodeRuntime` in Shared. It owns the Wi-Fi, provisioning,
   MQTT, configuration fetch/retry, OTA and peripheral lifecycle, exposes `begin(NodeRuntimeConfig)`
   and `loop()`, and delivers configuration, command and system-command callbacks. Each `main.cpp`
   shrinks to board setup, `ViewManager` creation and runtime callbacks.
4. **Wiegand peripheral.** Add a `WiegandI2CPeripheral : IPeripheral` to Shared (I2C `0x26`, 3-byte
   code, optional IRQ pin) using the existing `PeripheralManager`. Core2's `Rfid2Peripheral` is the
   pattern to follow.
5. Make a host C++ toolchain available in CI so the native tests (including the new view-model
   tests) run on every push.

**Done when.** No duplicated view logic between the two boards, both `main.cpp` files are under
~200 lines, and the view models have native tests running in CI.
