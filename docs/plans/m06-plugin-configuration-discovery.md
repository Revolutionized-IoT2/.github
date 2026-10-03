# M6. Consistent plugin configuration discovery and no static device state

Applies to: see the problem description. Status: snapshot from the September 2026 platform review. Verify against the code before starting work.
Index and dependencies: [plans/README.md](README.md). Backlog: [open-issues.md](../backlog/open-issues.md).

**Problem.** Four devices read configuration parameters but don't implement
`IDeviceWithConfiguration`, so the UI can't show which parameters they need:

- `AzureRelay`: `relayNamespace`, `connectionName`, `keyName`, `key`
- `EasyPLC`: `ipAddress`, `port`
- `FTP`: `ftpUsers`, `StorageIp`, `StorageUser`, `StoragePassword`, `StorageFolder`
- `Mqtt`: `clientId`, `serverUrl`, `userName`, `password`, `subscribeTopics`

`NetatmoBase` keeps the access token, refresh token, client id/secret, the configured flag and the
logger in `static` fields. `NetatmoWeather` and `NetatmoSecurity` therefore share one account
implicitly: configuring one overwrites the other, and two Netatmo accounts can't coexist.

## Steps

1. Implement `IDeviceWithConfiguration.GetConfigurationTemplate()` for the four devices, listing
   every parameter they read, with the same key spelling (`FTP` keeps its PascalCase `Storage*`
   keys so existing configurations still load).
2. Add a reflection test to both plugin test projects. For every catalog device, parse the keys it
   reads via `GetConfiguration<T>("...")` (or record them through a test helper) and assert that
   they all appear in its configuration template.
3. Replace the Netatmo statics with an injected `NetatmoAuthClient` keyed by `clientId`, registered
   as a singleton factory in `Plugin.cs`. Devices sharing a `clientId` share a token; different
   accounts get separate token files under `Data/`. Keep the current token file name for the first
   account so existing installations don't need to log in again.
4. Document the parameters of all four devices in `RIoT2.Net.Devices/README.md`.

**Done when.** Every catalog device returns a configuration template that covers its parameters,
the reflection test passes, and `NetatmoBase` has no static mutable state.
