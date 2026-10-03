# Docs drift check

Applies to: the documentation of every RIoT2 repository. It enforces the rules from
[ADR 0001](../../docs/adr/0001-documentation-structure.md), and checks the platform contracts in
[docs/contracts](../../docs/contracts/) against the code.

## Run it

From the workspace root (the folder that holds `.github` and the `RIoT2.*` repositories),
Python 3.9+ only:

```powershell
python .github\tools\docs-check\check_docs.py                 # all checks
python .github\tools\docs-check\check_docs.py --only links,env  # a subset
python .github\tools\docs-check\check_docs.py --list           # what each check does
python .github\tools\docs-check\test_check_docs.py             # self-test of the checker
```

- Exit code 1 means at least one ERROR (or a WARN, with `--warnings-as-errors`).
- Contract checks compare against the repositories that are present. Repositories that are
  missing are skipped, not reported.
- CI runs the same commands in
  [.github/workflows/docs-check.yml](../../.github/workflows/docs-check.yml):
  - on every hub change;
  - weekly (code in other repositories may have moved);
  - on demand;
  - as a reusable workflow that other repositories can call for their pull requests, with
    `repository` and `ref` inputs.

## Checks

| Check | Fails when |
|---|---|
| `links` | A relative link, an anchor, or a link to another RIoT2 repository doesn't resolve, or a `blob/<branch>` link doesn't use that repository's default branch (RIoT2.Elsa uses `master`). |
| `images` | An image in the hub isn't referenced by any document. Obsolete screenshots must be deleted. |
| `size` | A document is over 20 KB (error) or about 15 KB (warning). `CHANGELOG.md` is exempt. |
| `layout` | A repository lacks `README.md`, `AGENTS.md` (with its required sections and the hub link), `CLAUDE.md` (exactly `@AGENTS.md`) or `CHANGELOG.md` (with `## [Unreleased]`). Also fails on a `copilot-instructions.md` that isn't a pointer, a leftover `.github/upgrades`, or session hand-off or test-count text in a README or AGENTS.md. |
| `secrets` | A document contains a value from a local `launchSettings*.json` or `appsettings*.json` (ids, passwords, tokens, keys). |
| `mqtt` | The topic templates in `RIoT2.Core/Constants.cs`, `RIoT2.Ard.Shared/RIoT2Shared/include/riot2/Topics.h` and the Topics table of `mqtt-topics.md` differ. |
| `enums` | A `MqttTopic`, `NodeType` or `ValueType` member or number (wire format) isn't stated in the contract docs. |
| `env` | A `RIOT2_*`, `VITE_MQTT_*` or `ELSA_*` variable read by product code is missing from `env-vars.md`, or a variable documented as current is read by no code. Not-yet-implemented variables go under "Planned (not implemented)". |
| `routes` | An endpoint mapped in Orchestrator, Node, Devices, Elsa or InfluxDB code is missing from `http-api.md`. A documented endpoint that no code maps is a warning. |
| `proto` | The Orchestrator and Elsa `.proto` files define different contracts (only `csharp_namespace` may differ). |
| `coderefs` | A `` `RIoT2.X/path` `` reference in a current-state hub document points to a file that doesn't exist. Snapshots (reviews, designs, plans, backlog) are exempt. |

## When it fails

- **Contract findings mean the code and the docs disagree.** The code is the source of truth:
  fix the contract document in the same change. If the code is wrong, fix the code, or list the
  difference under "Known divergences" in that document.
- **Test projects don't count as product code** (`Tests/`, `*.Tests/`, `*Tests.cs`, `*.test.*`).
- **Extending the checker:** add a check function, register it in `CHECKS`, and add a test to
  `test_check_docs.py` that injects the drift and expects the error.
