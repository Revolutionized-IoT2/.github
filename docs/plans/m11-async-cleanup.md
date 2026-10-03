# M11. Remaining blocking and `async void` code (backlog item 4)

Applies to: see the problem description. Status: snapshot from the September 2026 platform review. Verify against the code before starting work.
Index and dependencies: [plans/README.md](README.md). Backlog: [open-issues.md](../backlog/open-issues.md).

**Inventory (verified by search).** The hits fall into four groups:

| Group | Locations | Action |
|---|---|---|
| **A. Intentional sync shims** for the synchronous device contract | `AsyncDeviceBase` lines 19–21; `DeviceServiceBase` 56, 58, 62, 70, 191; `CommandService` 28; `NodeConfigurationServiceBase` 70; the sync `ExecuteCommand` of `EasyPLC` 32, `Mqtt` 21, `Web` 15 | Keep, so existing plugins stay binary-compatible. Mark them `[Obsolete]` in the [M1](m01-split-core-packages.md) `RIoT2.Core.Devices` package. Make sure the host never calls them: `RIoT2.Net.Node/Program.cs:167` still calls the synchronous `DownloadPluginPackage`, so switch it to `DownloadPluginPackageAsync` now. |
| **B. Device code blocking on I/O** | **Devices:**<br>- `ApSystems` 195<br>- `ElectricityPrice` 172, 185<br>- `EufySecurity` 107, 117 (`Task.Delay(2000).Wait()`)<br>- `Hue` 46, 64, 159<br>- `Messaging` 42, 65<br>- `NetatmoSecurity` 106, 121, 129, 251, 258<br>- `NetatmoWeather` 28, 40, 65<br>- `WaterConsumption` 35, 87<br><br>**RasPi:**<br>- `FGBS222` 68, 138, 140<br>- `FGWPF102` 55–57, 179, 181<br>- `Models/ZWaveNode` 15, 24 (a constructor doing Z-Wave I/O) | Migrate each device to `AsyncDeviceBase` + `IAsyncCommandDevice` / `IAsyncRefreshableReportDevice`, which the host already supports (`EasyPLC` is the reference). Replace the `ZWaveNode` constructor with `static Task<ZWaveNode> CreateAsync(...)`. One device per PR, each with a lifecycle test following `EasyPlcLifecycleTests`/`AsyncDeviceLifecycleTests`. Do NetatmoWeather/Security together with [M6](m06-plugin-configuration-discovery.md) (the per-account auth client). |
| **C. `async void`** | **Core:** `NodeMqttService` 168 `_reportService_ReportUpdated`.<br><br>**Devices:** `EufySecurityService` 74 `client_MessageReceived`, and `.Wait()` on connect/disconnect at 205 and 222.<br><br>**RasPi:**<br>- `BluetoothService` 45 `mainLoop`: a long-running loop started as `async void`, with no cancellation; an exception crashes the node.<br>- `BluetoothService` 86 `onDeviceAdded`<br>- `RuuviTagListener` 76 `OnPropertiesChanged` | **Core:** report publishing goes through a bounded channel with one publisher loop (order kept, errors logged, backpressure).<br><br>**EufySecurityService:** incoming messages go into a channel; add async `StartAsync`/`StopAsync`.<br><br>**RasPi:**<br>- `mainLoop` becomes `Task RunAsync(CancellationToken)`, owned and awaited by the service's stop.<br>- The two Tmds.DBus callbacks stay `void` (the library has no `Task`-based signal API) but call a shared `FireAndForget(task, logger)` helper that observes and logs exceptions. |
| **D. Hosts** | Orchestrator `OrchestratorMqttService` 105 (deliberate backpressure behind a synchronous event) and 139 (`Dispose`); Elsa `RIoTLAppLifetimeExtension` 14 (`.Wait()` in `ApplicationStopping`); `MqttClient` 160 ([M10](m10-mqtt-client-robustness.md)) | Orchestrator 105 goes away with [M2](m02-system-text-json-persistence.md) step 4 (typed async storage events). Elsa: move the MQTT stop into an `IHostedService.StopAsync`. `MqttClient`: M10. |

Not counted as problems:

- `RasPi AI418ML` `Thread.Sleep(5)`: a deliberate ADC conversion wait.
- `CoverDisplay` 379: waiting for the blink task inside stop.
- `OnlineNodeService` 126: `.Result` after `Task.WhenAll`.
- `FTP/CustomLocalDataConnection` 56: the `Zhaobang.FtpServer` interface is synchronous. Documented and left as is.

## Steps

1. Group A host call site, and the Core `NodeMqttService` channel (group C). Small, and in Core/Node
   only.
2. Group C for the RasPi Bluetooth and Ruuvi code and `EufySecurityService`, plus the Elsa shutdown.
3. Group B device by device, starting with the ones on timers or refresh schedules, where blocking
   ties up Quartz threads: ElectricityPrice, WaterConsumption, ApSystems, Netatmo. Then the command
   paths: Hue, Messaging, EufySecurity, then the Z-Wave devices.
4. Turn on the threading analyzers from [M8](m08-dotnet10-migration.md) step 10 as warnings, with justified suppressions only in
   group A. With `TreatWarningsAsErrors` in CI this prevents regressions.

## Done when

- There is no `async void` left except the two DBus callbacks, which use the helper.
- VSTHRD002/VSTHRD100 are clean in Core, Node, Devices and RasPi apart from the suppressed group A
  shims.
- Every migrated device has a lifecycle test.
