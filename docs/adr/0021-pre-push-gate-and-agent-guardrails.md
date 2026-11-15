# 0021. A local pre-push gate, a red-branch alert and agent guardrails for CI

- Status: Accepted
- Date: 2026-11-15
- Applies to: every RIoT2 repository (`ci.yml`), `.github` (`tools/preflight`, `hooks`, reusable workflows)

## Context

On 2026-11-14 and 15 the hub's `main` was red for eleven pushes in a row, and the UI and the RIoT2.Tests
nightly were red as well. The causes were all things a check knew about, but nothing ran the check before
the push:

- a Markdown lint error, pushed again and again on top of the red branch;
- a shell script committed without its executable bit (a Windows checkout doesn't show it);
- `remote.ps1` and an nginx test that passed on Windows and failed on the Linux runner;
- an image pin edited by hand to a version that was never published;
- RIoT2.Core and RIoT2.Elsa tagged and released while their source `<Version>` stayed at the old
  version, so RIoT2.Tests imported two versions of the Core assemblies (CS1704).

The maintainer pushes directly to `main` (administrators may bypass branch protection), and so do the AI
agents that work in the workspace. `AGENTS.md` said what to run, but nothing checked that it ran.

## Decision

- **A pre-push gate.** `tools/preflight/preflight.py` runs, before each push, the checks CI runs for what
  the push changes: repository hygiene, a red default branch on GitHub, release tag versions, RIoT2.Core
  version sync, sibling repositories that CI clones, gitleaks on the pushed commits, markdownlint,
  actionlint, docs-check, the hub's tool self-tests, published image pins, and each repository's build
  and tests from `preflight.json`, plus the tests of the repositories that build against it. The git
  hook in `tools/preflight/git-hooks` runs it; `install-hooks.ps1` points every repository's
  `core.hooksPath` there. Checks that need Linux (shellcheck, bash 3.2, nginx, the compose stack) stay
  in CI.
- **No stacking on red.** The gate refuses a push to a default branch whose latest push or schedule run
  failed, unless `RIOT2_PREFLIGHT_FIXES_RED=1` says the push fixes it. The reusable `ci-alert.yml`, the
  last job of every `ci.yml`, opens an issue labelled `ci-red` per failing workflow and closes it when
  the workflow passes again.
- **CI checks the new failure classes too**: shell scripts must be executable (`secret-scan.yml`), the
  pinned images must be published (`deploy-check.yml`, `nightly-smoke.yml`), a release tag must equal
  the source `<Version>` (`nuget-publish.yml`), and no package pin may be above RIoT2.Core's source
  version (`dotnet-validate.yml`).
- **Agent guardrails.** `AGENTS.md` makes the gate and the CI follow-up rules. The hub's
  `hooks/riot2-guardrails.json` (the workspace's `.github/hooks`) and the Claude settings that
  `install-hooks.ps1` writes run `hooks/riot2_guard.py`, which denies `--no-verify`, changes to
  `core.hooksPath`, `RIOT2_PREFLIGHT_SKIP` and a push whose commit has no passed preflight, and after a
  push tells the agent to wait for CI. The `skills/ci-preflight` skill holds the procedures.
- The hub's Deploy check runs on every push, and skips its stack when `deploy/` didn't change, so its
  `deploy check` job can be a required check.

## Consequences

- A push takes longer: from seconds for documentation to a few minutes for a .NET change with its
  downstream tests. A preflight passed by hand for the same commit is not repeated by the hook.
- The gate is local. `git push --no-verify` still works for a person, so CI and the `ci-red` issue remain
  the backstop.
- Each new CI job or tool version must be mirrored in `preflight.json` or `preflight.py`.
- Developer machines need Python 3.9 or later on `PATH`, and Node.js for markdownlint and the UI.
