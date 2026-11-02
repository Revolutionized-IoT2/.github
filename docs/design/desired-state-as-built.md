# Design 7.2 as built: desired-state configuration and plugin updates

Applies to: Core, Orchestrator, Node and the firmware. How the phases of
[design 7.2](desired-state-configuration.md) were implemented, and where the code differs from
the design. The contracts are in [configuration.md](../contracts/configuration.md) and
[mqtt-topics.md](../contracts/mqtt-topics.md).

## As built: phases 2–3 (I16)

Core `1.8.0`, Node `1.5.0` and Orchestrator `1.5.0`, 2026-10-14. The contract is in
[configuration.md](../contracts/configuration.md#desired-state) and
[mqtt-topics.md](../contracts/mqtt-topics.md); divergence D1 (.NET presence not retained) is fixed:
`NodeMqttService` retains its presence and last will. Where the build differs from the text above:

- **Configuration commands are not conditional.** The orchestrator sends one on every presence and
  every save, with `revision` and `hash`, to every node. A retained status can be older than the
  node behind it (a node whose `Data/` was lost still has its old retained status), so the node
  decides: an applied hash costs one MQTT message and no fetch. Nothing resends on a status
  mismatch either, which also rules out a resend loop when a fetch keeps failing.
- **The hash** is SHA-256 of `Json.Serialize` of the document without its own `revision` and
  `hash` (device hashes included), and of each entry without its `hash` (`ConfigurationHash`). It
  is recomputed when the orchestrator loads, so it always matches what is served.
- **The device diff stays content-based** (phase 0) and ignores the per-device `hash`, so the first
  hashed configuration restarts nothing. A command for the applied hash while a configured device
  isn't running is fetched (`304`) and applied again, which keeps phase 0's retry of failed devices.
- **Status details.** Before its first configuration a node reports `applying` without a revision.
  `applying` is published when a fetched configuration is handed to the devices, not before the
  fetch. `failedDevices` includes entries whose class no loaded plugin provides.
- **Saved configuration** is under the host's content root (`/app/Data` in the image), not next to
  the executable, so every test host has its own.
- Two fixes the hash depends on: `?state=true` used to write the last command values into every
  stored configuration (it now works on a copy), and a configuration command sent for a save could
  carry the previous hash (the configuration snapshot is now refreshed before other services hear
  of the save). The plugin loader also skips abstract types (Core's `PluginBase`), which logged an
  error at every start.
- Tests: Node `NodeDesiredStateTests` (zero fetches and restarts on reconnect and orchestrator
  restart, start from the saved configuration, failed fetch, devices not running, an orchestrator
  without hashes, retained presence and status); RIoT2.Tests `DesiredStateNodeTests`,
  `DesiredStateOrchestratorTests`, `WorkflowRoutingTests` (sync state, legacy) and the end-to-end
  `EndToEndTests` (reconnect, orchestrator restart, start with the orchestrator down).

## As built: phase 5 (I19)

M5Core2 and M5Dial firmware `0.5.0`, 2026-11-01, in `RIoT2.Ard.Shared` (`NodeRuntime`,
`NodeStatus`); contract in [configuration.md](../contracts/configuration.md#desired-state). Divergence
D5 is fixed: firmware fetches `api/nodes/…`.

- The firmware keeps no saved configuration, so the applied hash lives in memory: after a restart
  it reports `applying` and fetches once.
- A command for the applied hash with state `applied` needs no work, even with failed devices
  (classes the build lacks, `Unknown class`; a fetch can't fix them), and drops a pending fetch for
  another hash. A repeat of the hash being fetched keeps the backoff. A `304` counts as applied.
- No `applying` before each fetch (the rebuild is synchronous), and an identical failure isn't
  published twice. At most four `failedDevices`, fewer if over the 512-byte packet; `error` ≤ 120
  characters.
- Host tests: `test_desired_state.py` (the firmware matrix rows) and `test_golden_messages.py`.

## As built: phase 4 (I35)

Core `1.19.0` (`PluginPackageInstaller`, `PluginCompatibility`) and Node `1.14.0`, 2026-11-02;
contract in [configuration.md](../contracts/configuration.md#plugins-net-node). Where the build differs
from decision 6:

- **The swap happens at the next start, not before the restart.** While the node runs it only
  stages: download, hash, extraction into `Plugins.new/`, `coreVersion`. The swap runs before
  plugins load, when no plugin file is in use (Windows can't move loaded DLLs), and an
  interrupted swap or rollback resumes from a journal (`Data/plugins.install.json`: `staged`,
  `backup`, `promote`, `installed`, `rollingBack`, `restoring`). A swap that throws counts as a
  failed install: the previous plugins go back and the package is refused. While a journal is
  past `staged`, nothing new is staged.
- **Contents move, not folders.** Compose bind-mounts `/app/Plugins`, which can't be renamed, so
  the node moves its entries to `Plugins.previous/` and those of `Plugins.new/` into it (a copy
  between file systems). `Plugins.new/` and `Plugins.previous/` are next to `Plugins/`, in the
  container: recreating the container drops them, and the node then stages the package again.
- **The marker is the refused package.** Rolled-back, incompatible, unsafe and unreadable packages
  go to `Data/plugins.rejected.json` (hash and file name), which stops the restart loop and any
  further download of the same package. A hash mismatch isn't kept (it may be a broken download).
  After a rollback the node exits with code 75 before the host starts, so `failed` is reported by
  the next check of the same package, after the restart. A first install (nothing in `Plugins/`
  before) isn't rolled back: the package stays with what of it loaded, and the log says why.
- **A refused package doesn't keep the previous configuration.** The devices are applied with the
  installed plugins and the status is `failed` with the reason (the applied revision stays), so a
  command for the same hash checks again (one sidecar request, no download).
- **"Fails to load"** means no plugin initialized or any DLL or plugin failed
  (`PluginLoader`, which also no longer stops at the first bad DLL).
- The `sha256` in the installed manifest is written by the node (the zip can't hold its own
  hash). A package installed by an older node has none; the file name identifies it, so upgrading
  the node doesn't reinstall it.
- Fixed on the way: the node saves the configuration before it restarts for a package (before,
  it started with the saved configuration naming the previous package and installed that one
  again, alternating on every start), and it re-reads the manifest after an install.
- Tests: RIoT2.Tests `PluginPackageInstallerTests` (compatibility rule, sidecar, staging, refusals,
  resume, rollback), Node `PluginUpdateTests` (applier outcomes, and the packed Devices zip
  installed, then a broken update rolled back once) and the golden `node-status-plugin-rejected`.

## As built: phase 6 (I36)

Orchestrator `1.16.0` and UI `1.8.0`, 2026-11-02; routes in [http-api.md](../contracts/http-api.md).

- **A cheap endpoint to poll.** `GET /api/nodes` asks every online node for its device states, so the
  UI polls the new `GET /api/v2/nodes/sync` every three seconds while the Configure page is open.
  Both report `configurationState` (the node's own `applying`, `applied`, `failed` or
  `pendingRestart`) and `failedDevices` besides the I16 fields, and `pluginManifest` falls back
  to the one in the retained status while the node is offline (with `coreVersion` since Core 1.19).
- **The badge.** "In sync" (orange with the devices that aren't running), "applying", "restarting"
  (`pendingRestart`), "failed" with the error, "offline" for a pending node that is away, and
  "legacy". The tooltip has the applied and saved revisions and the plugin package with its Core.
  A poll that fails keeps the last state without a snackbar. An offline node's device states are
  shown as unknown, and read again when it comes back.
- **Re-apply** (`POST /api/v2/nodes/{id}/configuration/apply`, Operator) sends the configuration
  command again; the node decides (design text above): a configuration it runs with every device
  running is only reported again, otherwise it is fetched (`304`) and applied, which restarts
  devices that aren't running. An offline node gets `409`.
- Tests: RIoT2.Tests `SyncEndpointReportsTheNodesStatusWithoutAskingThem`, the end-to-end
  `SyncEndpointFollowsAConfigurationChangeAndReapplyReachesTheNode` (`applying`, then revision 2 in
  sync, then a re-apply that fetches nothing), and the UI's `sync-status.test.cjs`.
