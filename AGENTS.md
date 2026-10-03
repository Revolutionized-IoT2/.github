# AGENTS.md — RIoT2 workspace guide

Instructions for AI coding agents (Copilot, Claude, and others) working anywhere in the RIoT2
platform. People can read it too. This file lives in the `.github` repository. It is written so it
can also be copied to the workspace root (`C:\Src\RIoT2\AGENTS.md`), which is not a repository.

## Start here

1. Read [docs/README.md](docs/README.md) (index) and
   [docs/architecture/overview.md](docs/architecture/overview.md) (components and flows).
2. Before changing anything that crosses a repository boundary (MQTT, REST, gRPC, configuration
   JSON, environment variables), read the matching file in [docs/contracts/](docs/contracts/).
3. Then read the target repository's own instructions: its `AGENTS.md`. Until that exists, read
   its `CLAUDE.md` and `.github/copilot-instructions.md`, plus its `README.md`.
4. When asked to "work on" a backlog item, plan or design, look up the ID in the
   [ID registry](docs/README.md#id-registry). Verify that the snapshot description still matches
   the code before changing anything.

## Workspace layout

- `C:\Src\RIoT2` contains about 16 sibling folders. **Each `RIoT2.*` folder and `.github` is a
  separate git repository** with its own history, CI and releases. The root is not a repository.
- Run git commands inside the repository you changed. Scope commits to that repository.
- `.localfeed\` is a local NuGet source holding unpublished `RIoT2.Core` packages. Add it as a
  restore source when a repository needs a Core version that hasn't been published yet.
- Ignore generated and vendored folders in searches and reviews: `.pio\`, `node_modules\`, `bin\`,
  `obj\`, `dist\`, `TestResults\`, `.vs\`. `.pio\libdeps` alone holds dozens of third-party
  READMEs.

## Repository map and commands

The shell is Windows PowerShell 5.1: no `&&`, `||` or `?.`. Use `;` and `if ($?) { … }`.
Commands run from the workspace root unless noted.
`$pio` = `"$env:USERPROFILE\.platformio\penv\Scripts\pio.exe"`.

| Repository | Kind | Build | Test |
|---|---|---|---|
| RIoT2.Core | .NET Standard 2.0 library (NuGet) | `dotnet build .\RIoT2.Core\RIoT2.Core.csproj` | `dotnet test .\RIoT2.Tests\RIoT2.Tests.csproj` |
| RIoT2.Net.Orchestrator | ASP.NET Core service | `dotnet build .\RIoT2.Net.Orchestrator\RIoT2.Net.Orchestrator.csproj` | `dotnet test .\RIoT2.Tests\RIoT2.Tests.csproj` |
| RIoT2.Net.Node | ASP.NET Core service | `dotnet build .\RIoT2.Net.Node\RIoT2.Net.Node.csproj` | `dotnet test .\RIoT2.Net.Node\Tests\RIoT2.Net.Node.Tests.csproj` |
| RIoT2.Net.Devices | Plugin library | `dotnet build .\RIoT2.Net.Devices\RIoT2.Net.Devices.csproj` | `dotnet test .\RIoT2.Net.Devices\Tests\RIoT2.Net.Devices.Tests.csproj` |
| RIoT2.Net.RasPi.Devices | Plugin library | `dotnet build .\RIoT2.Net.RasPi.Devices\RIoT2.Net.RasPi.Devices.csproj` | `dotnet test .\RIoT2.Net.RasPi.Devices\Tests\RIoT2.Net.RasPi.Devices.Tests.csproj` |
| RIoT2.Elsa | Elsa 3 server and Studio | `dotnet build .\RIoT2.Elsa\RIoT2.Elsa.sln` | `dotnet test .\RIoT2.Elsa\RIoT2.Elsa.Tests\RIoT2.Elsa.Tests.csproj` |
| RIoT2.Connector.InfluxDB | ASP.NET Core service | `dotnet build .\RIoT2.Connector.InfluxDB\RIoT2.Connector.InfluxDB.csproj` | `dotnet test .\RIoT2.Tests\RIoT2.Tests.csproj` |
| RIoT2.Tests | Cross-repository tests (project references to Core, Orchestrator, connector) | — | `dotnet test .\RIoT2.Tests\RIoT2.Tests.csproj` |
| RIoT2.UI | Vue 3 + Vite | in `RIoT2.UI`: `npm run build` | in `RIoT2.UI`: `npm run typecheck; npm test` |
| RIoT2.Mobile | .NET MAUI | `dotnet build .\RIoT2.Mobile\RIoT2.Mobile.csproj -f net9.0-windows10.0.19041.0` | `dotnet test .\RIoT2.Mobile\Tests\RIoT2.Mobile.Tests.csproj` |
| RIoT2.Matter | .NET libraries and Controller | `dotnet build .\RIoT2.Matter\RIoT2.Matter.sln -c Release` | `dotnet test .\RIoT2.Matter\RIoT2.Matter.sln -c Release`; Controller UI in `RIoT2.Matter\Controller\Ui`: `npm ci; npm run build; npm test` |
| RIoT2.Ard.Shared | Firmware library | build **both** consumers (next two rows) | `python .\RIoT2.Ard.Shared\tests\test_firmware_p1.py` (also `_p2`, `_architecture`; needs a C++14 compiler) |
| RIoT2.Ard.M5Core2.Node | ESP32 firmware | `& $pio run -d .\RIoT2.Ard.M5Core2.Node` | Ard.Shared host tests |
| RIoT2.Ard.M5Dial.Node | ESP32-S3 firmware | `& $pio run -d .\RIoT2.Ard.M5Dial.Node` | Ard.Shared host tests |
| RIoT2.Ard.WiegandI2C | ATtiny85 sketch | Arduino IDE (no CLI build) | Ard.Shared `test_firmware_p2.py` covers the driver |
| .github | Documentation hub, roadmap, screenshot tooling | — | Link check (see [docs/README.md](docs/README.md#maintaining-these-docs)) |

Run the smallest command that covers your change. Escalate to wider suites only when that one
passes, or when the change crosses repositories.

## Platform rules (apply everywhere)

**Contracts**

- MQTT topics, payloads, REST routes, gRPC and the configuration JSON are contracts between
  independently released repositories, including firmware that updates slowly.
- Change contracts **additively** only. Follow
  [mqtt-topics.md § Rules](docs/contracts/mqtt-topics.md#rules-for-changing-this-contract).
- Use `RIoT2.Core/Constants.cs` for topics and shared URLs. Don't hard-code them in .NET code.
  Firmware mirrors them in `RIoT2.Ard.Shared/RIoT2Shared/include/riot2/Topics.h`.
- JSON is camelCase. Use `Json.Serialize` / `Json.SerializeIgnoreNulls` from Core.
- New `deviceParameters` keys must be camelCase, because dictionary keys get camel-cased
  ([configuration.md C1](docs/contracts/configuration.md#known-divergences)).
- The two `.proto` files (Orchestrator `riot_trigger.proto`, Elsa `riot.proto`) must stay
  identical.

**Versions**

- `RIoT2.Core` targets .NET Standard 2.0. Keep its public API stable and additive.
- Consumers reference Core as a NuGet package. Don't swap that for a project reference, except
  in RIoT2.Tests.
- Release the Node image and the device plugin packages together. Plugins run inside the Node's
  Core version.

**Security** ([ADR 0002](docs/adr/0002-isolated-network-security-model.md))

- APIs are anonymous by design. Don't add mandatory authentication.
- No state changes in new `GET` endpoints, no ad-hoc per-endpoint auth.
- Validate all inputs.
- No credentials, IDs or IPs in images, docs or committed config. `launchSettings.json` holds
  local development values only.
- Never use raw ids as file paths.

**Automation** ([ADR 0003](docs/adr/0003-elsa-sole-automation-engine.md))

- Elsa 3 is the only engine. Don't reintroduce the internal rule engine, its models or NCalc.

**Firmware**

- Put reusable logic in `RIoT2.Ard.Shared`, not in one board's repository.
- A change to Ard.Shared is done only when both M5Core2 and M5Dial build.
- The command id `system.ota` is reserved.

**Async**

- Don't add `async void` (other than event handlers) or blocking `.Result` / `.Wait()` calls in
  services.
- Device work is cancellation-aware (`IAsyncDevice`, `AsyncDeviceBase`).

**Running services locally**

- Debug builds of the Node load `Data/local.configuration.json` and ignore MQTT configuration.
  That file may hold real credentials. Use Release builds when you run the stack.
- `dotnet publish` copies local `Data/*.json` (Node) and `StoredObjects/` (Orchestrator) into the
  output. Delete them from the output before running it (backlog item 20).
- A Mosquitto service may already be listening on `127.0.0.1:1883` on a developer machine. Don't
  publish test traffic to it. Run a separate broker on another address, as
  [tools/ui-screenshots](tools/ui-screenshots/README.md) does.

## Documentation rules

These are defined in [ADR 0001](docs/adr/0001-documentation-structure.md).

- Platform-wide facts go in `.github/docs/`, and only there. Per-repository docs **link** to
  them; they don't copy them.
- When your code change alters a contract, update the matching `docs/contracts/*.md` in the same
  task, and say so in your summary. If you find code and docs disagreeing, the code wins: fix the
  doc, or report the divergence.
- Per repository: `README.md` (people), `AGENTS.md` (agents), `CLAUDE.md` = `@AGENTS.md`,
  `CHANGELOG.md` (version notes).
- Don't put session hand-offs, test-pass counts or "next steps" in documentation. Use issues or
  pull request descriptions.
- When you finish a backlog item or plan step:
  - remove it from [docs/backlog/](docs/backlog/README.md);
  - tick it in [ROADMAP.md](ROADMAP.md);
  - describe any new behaviour in `docs/contracts/`, not in the design.
- Keep each file under about 15 KB, with one topic per file and a first line saying what it
  applies to. Write rules as "must" or "must not". Commands must work in PowerShell.
- Record significant decisions as ADRs in [docs/adr/](docs/adr/README.md).
