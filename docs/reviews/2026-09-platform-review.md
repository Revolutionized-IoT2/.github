# RIoT2 platform review (September 2026)

Applies to: all repositories. **Frozen historical record**: don't update it and don't use it for
the current state. Everything still actionable from the review moved to the documents listed
under [Where the rest went](#where-the-rest-went).

The review covered every RIoT2 repository: the bugs found and fixed, the open issues, maintainability
plans, designs, and architecture and feature proposals. This file keeps the verification results
(section 1) and the list of fixes applied (section 3).

## 1. Scope and verification

All 15 repositories were reviewed: Core, Orchestrator, Node, Devices, RasPi.Devices, Elsa,
Connector.InfluxDB, UI, Mobile, Matter (library, ControlBridge, Controller, OnOffSample),
Ard.Shared, Ard.M5Core2.Node, Ard.M5Dial.Node, Ard.WiegandI2C, and Tests.

Final verification (no `RIOT2_*` environment variables set):

| Component | Command | Result |
|---|---|---|
| RIoT2.Core | `dotnet build` | 0 warnings, 0 errors |
| RIoT2.Tests (Core, Orchestrator, Influx) | `dotnet test` | 212/212 passed (baseline: 8 of 194 failing on timeouts) |
| RIoT2.Net.Orchestrator | `dotnet build` | 0 warnings, 0 errors |
| RIoT2.Net.Node | `dotnet test` | 23/23 passed |
| RIoT2.Net.Devices | `dotnet test` | 31/31 passed (baseline 23) |
| RIoT2.Net.RasPi.Devices | `dotnet test` | 114/114 passed (baseline 111), warnings 1 → 0 |
| RIoT2.Matter | `dotnet test RIoT2.Matter.sln` | 56/56 passed (baseline 52), 0 warnings |
| RIoT2.Elsa | `dotnet test RIoT2.Elsa.sln` | 11/11 passed, NU1903 vulnerable SQLite warning fixed |
| RIoT2.Connector.InfluxDB | `dotnet build` | 0 warnings, 0 errors |
| RIoT2.Mobile | `dotnet test` + Windows build | 14/14 passed; Windows build fixed (it was failing) |
| RIoT2.UI | `npm test`, `npm run typecheck`, `npm run build` | 12/12 passed (baseline 8), type-check clean |
| RIoT2.Ard.M5Core2.Node / M5Dial.Node | `pio run` | Both boards build |
| Core compatibility | Every Core-consuming repo built against a package packed from current Core source | All compile, no source changes needed |

The ESP32 native unit tests (`RIoT2.Ard.Shared/tests`) need a host C++ compiler, and none was
available on the review machine, so they were not run. `RIoT2.Ard.WiegandI2C` has no PlatformIO
project, so it was reviewed but not built.

## 3. Fixes applied

### Security

| Area | Fix |
|---|---|
| Core `Utils/Json.cs` | `TypeNameHandling.Auto` deserialization (used on REST-posted and MQTT-advertised configuration, where `ReportTemplate.Model`/`CommandTemplate.Model` are `object`) now goes through a restrictive `RIoT2SerializationBinder`. It allows only RIoT2 assemblies, primitives, arrays and generic collections of allowed types, which closes a remote deserialization-gadget vector. |
| Core `NodeConfigurationServiceBase` | Plugin package file names are sanitized and zip extraction is blocked outside `Plugins/` (zip-slip). |
| Orchestrator `FileObjectStore`, `MatterBridgeService` | Path traversal through stored object ids/type names and Matter credential paths is blocked; bad input returns 400. |
| Node `DownloadController` | Rejects traversal, absolute paths and encoded separators. |
| Devices `WebhookController` | 64 KiB request limit; a null body returns 400 instead of a 500. |
| Devices `NetatmoBase`, sample configs | Tokens are no longer logged; sample secrets were removed from `ApSystems`/`Messaging`. |
| Elsa | The hard-coded JWT signing key was removed (`ELSA_IDENTITY_SIGNING_KEY` is required outside Development). The vulnerable `SQLitePCLRaw` is pinned to 2.1.12. |
| UI | `v-html` XSS in the cron tooltip was removed. `entrypoint.sh` no longer logs secrets, escapes values safely and uses `printenv`. nginx sends security headers. |
| Mobile | Android Auto Backup of preferences is disabled. |
| Firmware | OTA over HTTPS now validates the root CA. Wiegand26 parity is validated. MQTT port input is validated. The configuration download is capped at 32 KiB. |
| Matter | TLV nesting depth is limited, unterminated containers are rejected, and CASE rejects non-uncompressed ECDH keys. |
| All Dockerfiles | Baked-in sample MQTT credentials, IPs and fixed node/orchestrator GUIDs are removed. Previously, two containers started with defaults shared the same id. |

### Correctness and reliability

- **Core:** `ToEpoch()` handled local-time `DateTime` values incorrectly (all current callers pass
  `UtcNow`, so existing data is not affected). `AdvertisementData` parsed beacon payloads as ASCII
  instead of hex. Test timeouts were stabilized.
- **Orchestrator:** storage change events are now raised outside the storage lock, which removes a
  deadlock risk. Startup fails fast on missing or invalid required environment variables. There is
  a `/health` check that includes MQTT connection state.
- **Node / plugins:** the webhook service crashed when a webhook had no subscriber. Electricity
  price refresh had a precision bug. Hue used an `async void` listener. MQTT/Web commands were not
  awaited.   RFID reads failed on the first read and on short payloads, and the I2C interrupt only read 1 byte
    of the 3-byte Wiegand code. GPIO/serial resources in `CoverDisplay`/`UartService` were not
    disposed; the CoverDisplay buttons now stay active when the display auto-off timer fires. Devices/RasPi were aligned to Core `0.1.43` (the
  Node host version). Startup fails fast on missing environment variables, and `/health` was added.
- **Elsa / Influx:** `.Result`/`Task.WaitAll` sync-over-async calls in activities and UI hint
  providers were replaced with `await`. The gRPC trigger returns `InvalidArgument` for bad JSON
  instead of an internal error. `RIoTDataService` uses an injected `HttpClient` and escaped ids.
  Configuration is validated at startup. `/health` and `/healthz` were added.
- **UI:** the variable write called a REST endpoint that doesn't exist
  (`GET /api/variable/{id}/value`). Button state compared the whole report object instead of its
  value. Primitive equality was wrong. Several widgets used non-reactive watcher sources. Arrays
  were detected as entities. MQTT publish/subscribe ran before the client existed. Malformed MQTT
  messages crashed the app.
- **Mobile:** the Windows build failed because stale `obj/` output was being compiled.
- **Firmware:** the provisioning restart timer broke on `millis()` rollover.
- **Matter:** the UDP receive loop died if a datagram handler threw.

### Hygiene

- Build output and device logs that had been committed (`RIoT2.Core/bin`, `RIoT2.Net.Orchestrator/bin`,
  `RIoT2.Ard.M5Core2.Node/logs`) are untracked, and the `.gitignore` files now use generic
  `bin/`/`obj/` rules.
- Broken replacement characters (U+FFFD) were fixed in the Core, Node, Devices, RasPi and Matter
  ControlBridge docs, and stale documentation was corrected across all repositories.

All changes are uncommitted in each repository's working tree, ready for review.

## Where the rest went

| Review section | Now in |
|---|---|
| 2. Things the maintainer has to do | [backlog/README.md § Maintainer actions](../backlog/README.md#maintainer-actions) |
| 4. Upgrade notes | [guides/upgrading.md](../guides/upgrading.md) |
| 5. Open issues backlog | [backlog/open-issues.md](../backlog/open-issues.md), [backlog/optional-hardening.md](../backlog/optional-hardening.md) |
| 6. Maintainability implementation plans | [plans/](../plans/README.md) |
| 7. Architecture proposals | [architecture/target.md](../architecture/target.md), [design/](../design/README.md) |
| 8. Feature proposals | [features.md](../features.md) |
| 9. Suggested roadmap | [ROADMAP.md](../../ROADMAP.md) |
