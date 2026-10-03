# 0001. Documentation structure and AI instruction files

- Status: Accepted
- Date: 2026-10-03
- Applies to: all repositories

## Context

RIoT2 is split across about 15 repositories. Before this decision:

- Shared contracts (MQTT topics, environment variables) were copied into 9–11 files each and
  drifted apart.
- Each repository mixed `README.md`, `CLAUDE.md` and `.github/copilot-instructions.md` with no
  consistent split, and several repositories had no AI guidance at all.
- Session hand-offs, test counts and release notes lived in READMEs.
- The platform review was a single 114 KB file. AI tools read files in chunks of about 20 KB, so
  they could not take it in at once.

## Decision

1. The `.github` organization repository is the documentation hub for everything that spans
   repositories: architecture, contracts, guides, ADRs and roadmap, under `docs/`. The hub's
   [AGENTS.md](../../AGENTS.md) is the workspace-level guide for AI agents.
2. Each contract has one canonical document in `docs/contracts/`, which names the code that
   implements it. Other repositories link to it instead of copying it. When the code and the
   document disagree, the code wins and the document is fixed.
3. Every repository uses the same files:
   - `README.md` for people: purpose, build/run, configuration, links to the hub.
   - `AGENTS.md` for AI agents: exact commands, invariants, layout, pitfalls. It is the only AI
     instruction file with content.
   - `CLAUDE.md` contains only `@AGENTS.md`. `.github/copilot-instructions.md` is removed, or
     contains only a pointer to `AGENTS.md`.
   - `CHANGELOG.md` for version notes.
   - `docs/` only when the repository needs more than a README (for example RIoT2.Matter).
4. Writing rules:
   - One topic per file, under about 15 KB, with a descriptive file name.
   - A first line that says what the file applies to.
   - Rules written as instructions ("must", "must not").
   - Commands that can be pasted into Windows PowerShell (no `&&`).
   - Links to the source of truth instead of copies.
   - Not-yet-implemented designs kept under "Planned (not implemented)".
5. Short-lived material (hand-offs, test-pass counts, "next steps" for one session) goes in
   issues or pull requests, not in documentation.

## Consequences

- A contract change touches one document plus the code, not a dozen READMEs.
- Agents can find the right document from [docs/README.md](../README.md) and
  [AGENTS.md](../../AGENTS.md) without reading every repository.
- Per-repository documents get shorter. All repositories were migrated on 2026-10-03, and
  `RIoT2.Matter` moved its detail into its own `docs/` folder.
- The workspace root (`C:\Src\RIoT2`) is not a repository. The hub `AGENTS.md` is written so it
  can also be copied there.

## Alternatives considered

- **Documentation in RIoT2.Core.** Core owns the contract code, but it is a library package. The
  organization repository is already the platform landing page and is not versioned with any
  single component.
- **A separate documentation site.** More tooling for a single maintainer. Plain Markdown in Git
  works for people, GitHub and AI tools alike.
- **Keeping `CLAUDE.md` and `copilot-instructions.md` as separate full files.** They had already
  diverged. Both tools can read `AGENTS.md` (Claude through the `@AGENTS.md` import).
