---
name: ci-preflight
description: Before pushing any RIoT2 repository, run the preflight and fix what it reports; after pushing, watch CI and fix a red run before anything else. Use when committing, pushing, tagging a release, moving a deploy pin, or when CI, a ci-red issue or a nightly run is red.
---

# CI preflight and red CI

Applies to: every RIoT2 repository. Background: [ADR 0021](../../docs/adr/0021-pre-push-gate-and-agent-guardrails.md),
[tools/preflight](../../tools/preflight/README.md), [CI guide](../../docs/guides/ci.md).

## Before a push

1. Finish the change and commit it in its own command. The preflight checks the committed `HEAD` and
   needs a clean working tree; commit or stash anything else.
2. Run the preflight for that repository from the workspace root:

   ```powershell
   python .\.github\tools\preflight\preflight.py --repo .\<Repository>
   ```

3. Fix every `FAIL`. Commit the fix and run the preflight again until it passes. Read the `warn` lines:
   a sibling that is ahead must be pushed first, and a Linux-only check runs only in CI.
4. Push in a separate command. Never use `--no-verify`, never change `core.hooksPath`, and never set
   `RIOT2_PREFLIGHT_SKIP`; the guardrail hook denies them.
5. In a change across repositories, push the producer first (Core, then Orchestrator or Matter, then
   their consumers, Tests and UI last), with a preflight for each.

## After a push

1. List the workflow runs of the pushed commit (GitHub Actions, the repository's `main`, newest first),
   and wait until every run completes. The hub also runs `Deploy check` and `Docs drift check`.
2. Green: report it to the user, with the run links.
3. Red: fix it before any other work, as below. Don't end the task on a red run without saying so.

## Fixing red CI

1. Find the failed run and get the failed jobs' logs. Read the first `##[error]` and the lines above it.
   The last lines are usually cleanup noise.
2. Classify it, and reproduce it locally when the class allows:

   | Symptom | Usual cause | Fix |
   |---|---|---|
   | `Permission denied` running a `.sh` | committed without the executable bit | `git update-index --chmod=+x <file>` |
   | markdownlint `MDxxx` | Markdown style | Fix the line; `npx markdownlint-cli2@0.23.2 <file>` |
   | `error CS…` / warnings as errors | CI builds with `-p:CI=true` | `dotnet build <sln> -c Release -p:CI=true` |
   | CS1704 "same simple name … already imported" | a source `<Version>` below a released tag | Set `<Version>` in `Directory.Build.repo.props` to the tag |
   | `… not found` pulling `ghcr.io/…` | a deploy pin to an unpublished tag | Pin the released tag; let the release's deploy PR move it |
   | passes on Windows, fails on Linux | paths, permissions, ports below 1024, text-mode streams | Make the code portable; see `AGENTS.md` |
   | a sibling's change missing | the sibling wasn't pushed first | Push the sibling, then re-run the job |

3. Fix, commit, and run the preflight. It refuses to push onto a red default branch, so push the fix with
   `RIOT2_PREFLIGHT_FIXES_RED=1` set for that one push.
4. Watch the new run. The `ci-red` issue closes when the workflow passes again.
5. A workflow fixed in the hub (`.github/workflows/*.yml@main`) doesn't reach a **re-run**: it keeps the
   reusable workflow's old commit. Start a new run instead (`workflow_dispatch` on the default branch).

## Releases and deploy pins

- Before tagging `x.y.z`: bump `<Version>` (`Directory.Build.repo.props`), `package.json` or `VERSION`
  to the tag, add the version to `CHANGELOG.md`, commit, run the preflight, push, wait for green, and then
  tag that commit. The preflight checks the tag again when it is pushed.
- Never edit an image pin in `.github/deploy` by hand. The release opens a `deploy/<image>-<version>`
  pull request after the image is published; merge those in release order.
