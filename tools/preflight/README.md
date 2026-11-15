# Preflight: CI's checks before a push

Applies to: every RIoT2 repository. Decided in [ADR 0021](../../docs/adr/0021-pre-push-gate-and-agent-guardrails.md).

`preflight.py` runs, before a push, the checks CI runs, for what the push changes. A git `pre-push` hook
runs it for every push, and agents run it by hand before they push. If it fails, the push stops: CI would
have failed the same way.

## Set up once per machine

```powershell
powershell -File .github\tools\preflight\install-hooks.ps1
```

This sets `core.hooksPath` of every RIoT2 repository to [git-hooks](git-hooks), copies the hub's
`AGENTS.md` to the workspace root, and writes the Claude Code hook settings (`.claude/settings.json` at the
workspace root). Run it again after a pull that changes this folder; `-Uninstall` removes the git hook.
It needs Python 3.9 or later on `PATH`, and Node.js for markdownlint and the npm projects.

## Run it

```powershell
python .github\tools\preflight\preflight.py --repo .\RIoT2.UI    # what a push of the current branch sends
python .github\tools\preflight\preflight.py --full                # every check, in the current repository
python .github\tools\preflight\preflight.py --quick               # no builds or tests
python .github\tools\preflight\preflight.py --only dotnet,docs    # some checks again
```

A passing run is recorded for its commit (`.git/riot2-preflight.json`, only with a clean working tree);
the hook then runs only the push-specific checks again. Logs of failed builds and tests are in
`%TEMP%\riot2-preflight`.

## Checks

| Check | Runs when | What it does |
|---|---|---|
| `hygiene` | always | Every tracked `*.sh` is `100755`; no merge conflict markers; no `.env`, `local.configuration.json`, keys or certificates committed; LF where `.gitattributes` says `eol=lf`; warns on files over 5 MB |
| `red-main` | a push to the default branch | Fails when the latest push or schedule run of any workflow failed on GitHub ([below](#a-red-default-branch)) |
| `tags` | an `x.y.z` tag is pushed | `<Version>` in `Directory.Build.repo.props`, `version` in `package.json` and `VERSION` must equal the tag; warns on a tag older than the newest one and on a `CHANGELOG.md` without it. A tag push runs every check |
| `core-sync` | Core, Tests, or a `Directory.*.props` changed | No `RIoT2.Core.*` or `RIoT2.Connector.Sdk` pin above RIoT2.Core's source `<Version>`, and no source `<Version>` (Core, Elsa) behind its newest tag |
| `siblings` | the repository's CI clones others | Fails when a sibling has commits that aren't on its default branch (push the producer first); warns when one is behind or has uncommitted changes |
| `secrets` | always | gitleaks on the pushed commits, with the repository's `.gitleaks.toml` (pinned, checksum-verified download) |
| `markdown` | hub Markdown changed | markdownlint-cli2, the version CI's action uses |
| `workflows` | a workflow changed | actionlint (pinned, checksum-verified download) |
| `docs` | always | [docs-check](../docs-check/README.md); errors in other repositories only warn |
| `python` | a hub tool changed | The tool's self-tests |
| `pins` | hub `deploy/` changed | Every pinned RIoT2 image is published ([pins.py](../compose-smoke/pins.py)) |
| `shellcheck` | a script changed and shellcheck is installed | shellcheck |
| `dotnet` | code changed (not only docs or `.github/`) | The `ci.yml` build and tests, Release, `-p:CI=true` (warnings are errors, as in CI) |
| `npm` | code changed (not only docs or `.github/`) | `npm ci` when `node_modules` is missing, then the scripts CI runs |
| `firmware` | code changed (not only docs or `.github/`) | The Ard.Shared host tests with a C++ compiler, and PlatformIO builds when installed |
| `downstream` | code changed (not only docs or `.github/`) | The tests of the repositories whose CI builds against this one's default branch (`downstream` in [preflight.json](preflight.json)) |

[preflight.json](preflight.json) mirrors each repository's `ci.yml` inputs. When a `ci.yml` changes what it
builds or tests, change `preflight.json` in the same change.

Linux-only checks stay in CI: shellcheck where it isn't installed, the bash 3.2 run, nginx, the compose
stack and the installer. Watch the CI run after every push.

## A red default branch

When CI fails on a default branch, the repository gets an issue labelled `ci-red`, and the gate refuses
pushes to that branch. Fix the failure first. Push the fix with the variable set, so the gate lets it
through:

```powershell
$env:RIOT2_PREFLIGHT_FIXES_RED = '1'; git push; Remove-Item Env:RIOT2_PREFLIGHT_FIXES_RED
```

A person who decides to skip a check can set `RIOT2_PREFLIGHT_SKIP=check,check`. Agents must not.

## Agent guardrails

[hooks/riot2_guard.py](../../hooks/riot2_guard.py) runs before and after every shell command of a Copilot
agent ([hooks/riot2-guardrails.json](../../hooks/riot2-guardrails.json), the workspace's `.github/hooks`)
and of Claude Code (the settings `install-hooks.ps1` writes). It denies `git push --no-verify`, changes to
`core.hooksPath`, `RIOT2_PREFLIGHT_SKIP`, and a push of a commit without a passed preflight. After a push,
it tells the agent to wait for the CI run. The procedures are in the
[ci-preflight skill](../../skills/ci-preflight/SKILL.md).

Self-test: `python tools/preflight/test_preflight.py` (the hub's CI runs it).
